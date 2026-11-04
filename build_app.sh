#!/bin/bash
# 编译打包两个 app：添加SSH.app（新增主机）、SSH 主机.app（终端里选主机）
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

mkdir -p build/tmp build/ModuleCache

cc() {
  TMPDIR="$DIR/build/tmp" swiftc -module-cache-path "$DIR/build/ModuleCache" -O "$1" -o "$2" -framework Cocoa
}

cc SSHHosts.swift build/sshhosts

package_app() {
  local app="$1" bin="$2" plist="$3" icon="$4"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$bin" "$app/Contents/MacOS/$(basename "$bin")"
  cp "$plist" "$app/Contents/Info.plist"
  cp "$icon" "$app/Contents/Resources/AppIcon.icns"
  printf '%s\n' "$DIR" > "$app/Contents/Resources/tools.path"
  codesign --force --sign - "$app" >/dev/null 2>&1 || true
}

package_app "添加SSH.app" build/sshhosts Info.plist icons/add.icns
package_app "SSH 主机.app" build/sshhosts Info-SSHHosts.plist icons/hosts.icns

echo "built: $DIR/添加SSH.app"
echo "built: $DIR/SSH 主机.app"
