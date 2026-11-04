#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""新增一台 SSH 主机：写入 hosts.json -> 重新生成 -> 安装到 ssh / iTerm2 / wssh。

用法:
  add_host.py --alias demo --host 1.2.3.4 --port 22 --user root --password-stdin --env prod
  add_host.py ... --yes          # 别名已存在时覆盖
  add_host.py ... --no-install   # 只生成文件，不动 ~/.ssh 和 iTerm2
  add_host.py ... --json         # 输出机器可读结果（GUI 用）

退出码: 0 成功 / 2 参数非法 / 3 别名已存在 / 4 安装失败
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

BASE = os.path.dirname(os.path.abspath(__file__))
HOSTS_JSON = os.path.join(BASE, "hosts.json")

ENVS = {
    "prod": ("#1f6feb", "生产"),
    "pre":  ("#bf8700", "预生产"),
    "test": ("#8250df", "测试"),
    "other": ("#6e7781", "其他"),
}

ALIAS_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
HOST_RE = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$")


def fail(code, msg):
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
    sys.exit(code)


def load_hosts():
    if not os.path.exists(HOSTS_JSON):
        return []
    with open(HOSTS_JSON, encoding="utf-8") as f:
        return json.load(f)


def save_hosts(hosts):
    fd, tmp = tempfile.mkstemp(dir=BASE, prefix=".hosts.", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(hosts, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, HOSTS_JSON)


def run(cmd, cwd=BASE, timeout=120):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--alias", required=True)
    ap.add_argument("--name", default="")
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, default=22)
    ap.add_argument("--user", required=True)
    ap.add_argument("--password-stdin", action="store_true")
    ap.add_argument("--password", default="")
    ap.add_argument("--env", choices=list(ENVS), default="prod")
    ap.add_argument("--tags", default="")
    ap.add_argument("--original", default="", help="编辑时原别名（用于重命名）")
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--no-install", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    alias = a.alias.strip()
    host = a.host.strip()
    user = a.user.strip()
    name = a.name.strip() or f"{alias} ({host})"
    password = sys.stdin.readline().rstrip("\n") if a.password_stdin else a.password

    if not ALIAS_RE.match(alias):
        fail(2, "别名只能包含字母、数字、点、下划线、中划线，且不能以符号开头")
    if not HOST_RE.match(host):
        fail(2, "主机/IP 格式不正确")
    if not (1 <= a.port <= 65535):
        fail(2, "端口必须在 1-65535 之间")
    if not user:
        fail(2, "用户名不能为空")
    if not password:
        fail(2, "密码不能为空")

    color, env_tag = ENVS[a.env]
    tags = [env_tag] + [t.strip() for t in a.tags.split(",") if t.strip()]

    hosts = load_hosts()
    original = a.original.strip() or alias
    existing = next((i for i, h in enumerate(hosts) if h["alias"] == original), None)
    if a.original and existing is None:
        fail(2, f"要编辑的主机 {original} 不存在")
    # 新别名不能和别的主机冲突（自己除外）
    clash = next((i for i, h in enumerate(hosts) if h["alias"] == alias and i != existing), None)
    if clash is not None:
        fail(3, f"别名 {alias} 已被占用（{hosts[clash]['host']}:{hosts[clash]['port']}）")
    if existing is not None and not a.yes and not a.original:
        fail(3, f"别名 {alias} 已存在（{hosts[existing]['host']}:{hosts[existing]['port']}）")

    entry = {
        "alias": alias,
        "name": name,
        "host": host,
        "port": a.port,
        "user": user,
        "password": password,
        "tags": list(dict.fromkeys(tags)),
        "color": color,
    }
    if existing is None:
        hosts.append(entry)
        action = "added"
    else:
        hosts[existing] = entry
        action = "updated"
    save_hosts(hosts)

    rc, out = run([sys.executable, os.path.join(BASE, "gen_all.py")])
    if rc != 0:
        fail(2, "生成配置失败：\n" + out.strip())

    if not a.no_install:
        rc, out = run(["bash", os.path.join(BASE, "install.sh")])
        if rc != 0:
            fail(4, "写入 ssh / iTerm2 失败：\n" + out.strip()[-1500:])

    print(json.dumps({
        "ok": True,
        "action": action,
        "alias": alias,
        "name": name,
        "host": host,
        "port": a.port,
        "user": user,
        "profile": name,
        "command": f"ssh {alias}",
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
