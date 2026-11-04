#!/bin/bash
# 生成两个 .icns：icons/hosts.icns（SSH 主机）、icons/add.icns（添加SSH）
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
mkdir -p build/tmp build/ModuleCache build/icons icons

TMPDIR="$DIR/build/tmp" swiftc -module-cache-path "$DIR/build/ModuleCache" -O make_icons.swift -o build/make_icons -framework Cocoa
./build/make_icons build/icons

build_icns() {
  local src="$1" out="$2"
  local set="build/$(basename "$out" .icns).iconset"
  rm -rf "$set"; mkdir -p "$set"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$src" --out "$set/icon_${s}x${s}.png" >/dev/null
    local d=$((s * 2))
    sips -z "$d" "$d" "$src" --out "$set/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$set" -o "$out"
  echo "wrote $out"
}

build_icns build/icons/icon-hosts.png icons/hosts.icns
build_icns build/icons/icon-add.png icons/add.icns
