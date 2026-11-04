#!/bin/bash
# 可选升级：用 ~/.ssh/work-info-credentials 里的密码批量装公钥，之后 ssh 免密、密码表可删。
# 会修改目标服务器的 ~/.ssh/authorized_keys，所以默认演练；确认后加 -y。
#   ./setup-ssh-keys.sh        # 只打印清单
#   ./setup-ssh-keys.sh -y     # 真正执行
set -uo pipefail

APPLY=0
[[ "${1:-}" == "-y" ]] && APPLY=1

CRED="${HOME}/.ssh/work-info-credentials"
[[ -r "$CRED" ]] || CRED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/credentials.tsv"
[[ -r "$CRED" ]] || { echo "找不到密码表 work-info-credentials"; exit 1; }

command -v sshpass >/dev/null || { echo "缺少 sshpass： brew install hudochenkov/sshpass/sshpass"; exit 1; }
[[ -f "$HOME/.ssh/id_rsa.pub" ]] || ssh-keygen -t rsa -b 4096 -N "" -f "$HOME/.ssh/id_rsa"

while IFS=$'\t' read -r key pw alias; do
  [[ "$key" =~ ^# || -z "${key:-}" || -z "${pw:-}" ]] && continue
  user="${key%@*}"
  hostport="${key#*@}"
  host="${hostport%:*}"
  port="${hostport##*:}"
  if [[ $APPLY -eq 0 ]]; then
    echo "[dry-run] ssh-copy-id -p ${port} ${user}@${host}   (${alias})"
    continue
  fi
  echo "==> ${alias}: ${user}@${host}:${port}"
  sshpass -p "$pw" ssh-copy-id \
    -o StrictHostKeyChecking=accept-new \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o ConnectTimeout=10 \
    -p "$port" "${user}@${host}" </dev/null \
    && echo "    OK" || echo "    失败（密码过期或禁用密码登录）"
done < "$CRED"

echo
echo "完成后测试： ssh jss"
