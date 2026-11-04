#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""由 hosts.json 生成三份产物：
   1. ssh_config_work      -> SSH 别名
   2. dynamic-profiles.json -> iTerm2 Dynamic Profiles
   3. credentials.tsv      -> askpass 用的 用户@主机:端口 -> 密码
"""
import json
import os
import uuid

BASE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser("~")
NS = uuid.UUID("6f9619ff-8b86-d011-b42d-00c04fc964ff")


def rgb(hex_color):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return {"Red Component": r, "Green Component": g, "Blue Component": b,
            "Color Space": "sRGB"}


with open(os.path.join(BASE, "hosts.json"), encoding="utf-8") as f:
    HOSTS = json.load(f)

# ---------- 1. ssh config ----------
lines = [
    "# ============================================================",
    "# work-info.md 中的 SSH 主机（由 gen_all.py 生成，勿手改）",
    "# 数据源: hosts.json",
    "# 安装位置: ~/.ssh/config.work，由 ~/.ssh/config 顶部 Include",
    "# 用法: ssh jss / ssh zeil-master / ssh pre-239 ...",
    "# ============================================================",
    "",
]
for h in HOSTS:
    lines += [
        f"# {h['name']}",
        f"Host {h['alias']}",
        f"    HostName {h['host']}",
        f"    Port {h['port']}",
        f"    User {h['user']}",
        "",
    ]
lines += ["# ---------- 公共参数 ----------"]
for h in HOSTS:
    lines.append("Host " + h["alias"])
lines += [
    "    ServerAliveInterval 30",
    "    ServerAliveCountMax 4",
    "    TCPKeepAlive yes",
    "    StrictHostKeyChecking accept-new",
    "    NumberOfPasswordPrompts 1",
    "    AddKeysToAgent yes",
    "    UseKeychain yes",
    "",
]
with open(os.path.join(BASE, "ssh_config_work"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

# ---------- 2. iTerm2 dynamic profiles ----------
profiles = []
for h in HOSTS:
    profiles.append({
        "Name": h["name"],
        "Guid": str(uuid.uuid5(NS, "work-info:" + h["alias"])).upper(),
        "Dynamic Profile Parent Name": "Default",
        "Custom Command": "Yes",
        "Command": f"{HOME}/.local/bin/wssh {h['alias']}",
        "Tags": h.get("tags") or [],
        "Badge Text": h["alias"],
        "Silence Bell": True,
        "Scrollback Lines": 10000,
        "Working Directory": HOME,
        "Use Italic Font": True,
        "Use Bold Font": True,
        "Tab Color": rgb(h.get("color") or "#1f6feb"),
    })
with open(os.path.join(BASE, "dynamic-profiles.json"), "w", encoding="utf-8") as f:
    json.dump({"Profiles": profiles}, f, ensure_ascii=False, indent=2)
    f.write("\n")

# ---------- 3. 凭据表 ----------
with open(os.path.join(BASE, "credentials.tsv"), "w", encoding="utf-8") as f:
    f.write("# key(user@host:port)\tpassword\talias\n")
    for h in HOSTS:
        f.write(f"{h['user']}@{h['host']}:{h['port']}\t{h['password']}\t{h['alias']}\n")

print(f"hosts={len(HOSTS)}  profiles={len(profiles)}")
