#!/usr/bin/env bash
# 一键导出：Windows / Linux / Web / Android
# 用法: ./export_all.sh [--only android|web,linux] [--godot /path/to/godot]
set -uo pipefail

GODOT="${GODOT:-godot}"
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --godot) GODOT="$2"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

if ! command -v "$GODOT" >/dev/null 2>&1 && [[ ! -x "$GODOT" ]]; then
  echo "找不到 Godot：$GODOT（用 --godot 指定路径）"; exit 1
fi

mkdir -p build/{windows,linux,web,android}

want() {
  [[ -z "$ONLY" ]] && return 0
  [[ ",$ONLY," == *",$1,"* ]]
}

run() {
  local name="$1" preset="$2"
  echo "── 导出 $name ──"
  "$GODOT" --headless --path . --export-release "$preset" 2>&1 | tail -3
  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then echo "  ✖ $name 失败（$rc）"; return $rc; fi
  echo "  ✔ $name"
}

rc=0
want windows && { run "Windows" "Windows Desktop" || rc=1; }
want linux   && { run "Linux"   "Linux"           || rc=1; }
want web     && { run "Web"     "Web"             || rc=1; }
want android && { run "Android" "Android"         || rc=1; }

echo
echo "产物："
find build -maxdepth 2 -type f \( -name "*.exe" -o -name "*.x86_64" -o -name "index.html" -o -name "*.apk" \) -printf "  %p  (%s bytes)\n" 2>/dev/null
exit $rc
