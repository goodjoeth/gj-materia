#!/usr/bin/env bash
# make_icon_mac.sh: macos/icon/AppIcon.icns (and AppIcon-1024.png, for an iOS build) from
# tools/make_icon_mac.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
swift "$ROOT/tools/make_icon_mac.swift" "$T/1024.png" "$ROOT/macos/icon/goodjoe-logo.png"
mkdir -p "$T/AppIcon.iconset" "$ROOT/macos/icon"
for s in 16 32 128 256 512; do
  sips -z $s $s "$T/1024.png" --out "$T/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$T/1024.png" --out "$T/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$T/AppIcon.iconset" -o "$ROOT/macos/icon/AppIcon.icns"
cp "$T/1024.png" "$ROOT/macos/icon/AppIcon-1024.png"
rm -rf "$T"
echo "macos/icon/AppIcon.icns"
