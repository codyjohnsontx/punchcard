#!/usr/bin/env bash
# Generates an .icns from a 1024x1024 PNG using only tools that ship with macOS.
# Usage: scripts/make-icon.sh [source.png] [output.icns]
set -euo pipefail

src="${1:-Packaging/icon-1024.png}"
out="${2:-dist/AppIcon.icns}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset" "$(dirname "$out")"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$src" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$src" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset" -o "$out"
