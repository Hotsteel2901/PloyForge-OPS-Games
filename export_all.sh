#!/usr/bin/env bash
# One-click export script for PolyForge: Ops (Linux/macOS/WSL)
# Usage:
#   ./export_all.sh
#   GODOT=/path/to/godot ./export_all.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-godot}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "Godot not found: $GODOT"
    echo "Download the matching export templates from the Godot editor"
    echo "(Editor -> Manage Export Templates) or set the path explicitly:"
    echo "  GODOT=/path/to/godot ./export_all.sh"
    exit 1
fi

export_platform() {
    local preset="$1"
    local out="$2"
    local dir
    dir=$(dirname "$out")
    mkdir -p "$dir"
    echo "Exporting $preset -> $out ..."
    "$GODOT" --headless --path "$ROOT" --export-release "$preset" "$out"
    echo "  OK: $out"
}

export_platform "Windows Desktop" "build/windows/PolyForgeOps.exe"
export_platform "Linux"           "build/linux/PolyForgeOps.x86_64"
chmod +x "$ROOT/build/linux/PolyForgeOps.x86_64"
export_platform "Web"             "build/web/index.html"

echo ""
echo "All exports complete."
echo "Web build must be served over HTTP (not file://):"
echo "  cd build/web && python3 -m http.server 8000"
