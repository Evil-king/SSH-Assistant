#!/bin/bash
# 安装 work-info.md 的 SSH 信息到 ssh / iTerm2 / wssh（幂等，自动备份 ~/.ssh/config）
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_DIR="$HOME/.ssh"
BIN_DIR="$HOME/.local/bin"
ITERM_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "==> 1/6 目录与权限"
mkdir -p "$SSH_DIR" "$BIN_DIR" "$ITERM_DIR"
chmod 700 "$SSH_DIR"

echo "==> 2/6 SSH 别名 -> ${SSH_DIR}/config.work"
cp "$SRC/ssh_config_work" "$SSH_DIR/config.work"
chmod 600 "$SSH_DIR/config.work"
touch "$SSH_DIR/config"
if ! grep -q "config.work" "$SSH_DIR/config"; then
  cp "$SSH_DIR/config" "$SSH_DIR/config.bak.${STAMP}"
  { echo "# >>> work-info.md managed by install.sh >>>"
    echo "Include ${SSH_DIR}/config.work"
    echo "# <<< work-info.md managed by install.sh <<<"
    cat "$SSH_DIR/config"
  } > "$SSH_DIR/config.new"
  mv "$SSH_DIR/config.new" "$SSH_DIR/config"
fi
chmod 600 "$SSH_DIR/config"

echo "==> 3/6 密码表 + askpass 助手"
cp "$SRC/credentials.tsv" "$SSH_DIR/work-info-credentials"
cp "$SRC/work-info-askpass" "$SSH_DIR/work-info-askpass"
chmod 600 "$SSH_DIR/work-info-credentials"
chmod 700 "$SSH_DIR/work-info-askpass"

echo "==> 4/6 wssh 命令"
cp "$SRC/wssh" "$BIN_DIR/wssh"
chmod 755 "$BIN_DIR/wssh"

echo "==> 5/6 iTerm2 Dynamic Profiles"
cp "$SRC/dynamic-profiles.json" "$ITERM_DIR/work-info.json"
chmod 644 "$ITERM_DIR/work-info.json"
touch "$ITERM_DIR" 2>/dev/null || true

echo "==> 6/6 两个 app 与命令"
mkdir -p "$HOME/Applications"
for app in "添加SSH.app" "SSH 主机.app"; do
  rm -rf "$HOME/Applications/$app"
  cp -R "$SRC/$app" "$HOME/Applications/$app"
  printf '%s\n' "$SRC" > "$HOME/Applications/$app/Contents/Resources/tools.path"
done
cp "$SRC/add-ssh-host" "$BIN_DIR/add-ssh-host"
cp "$SRC/ssh-hosts" "$BIN_DIR/ssh-hosts"
chmod 755 "$BIN_DIR/add-ssh-host" "$BIN_DIR/ssh-hosts"
chmod 600 "$SRC/hosts.json" 2>/dev/null || true

echo ""
echo "完成，自检："
for h in jss supflops zeil-master pre-239 aigc; do
  printf '  %-13s ' "$h"
  ssh -G "$h" 2>/dev/null | awk '/^hostname /{h=$2}/^port /{p=$2}/^user /{u=$2}END{printf "%-22s ", u"@"h":"p}'
  if WORK_SSH_HOST="$(ssh -G "$h" | awk '/^hostname /{print $2}')" \
     WORK_SSH_PORT="$(ssh -G "$h" | awk '/^port /{print $2}')" \
     WORK_SSH_USER="$(ssh -G "$h" | awk '/^user /{print $2}')" \
     "$SSH_DIR/work-info-askpass" | grep -q .; then
    echo "密码已记住"
  else
    echo "无密码记录"
  fi
done
echo ""
echo "iTerm2 里按 Cmd+Shift+O 搜索 JSS / 预生产 / supflops 即可直达（也已装好 wssh 命令）。"
