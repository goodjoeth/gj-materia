#!/usr/bin/env bash
# make_installer.sh: build/installer/GJ Materia Installer.app (universal, arm64 + x86_64) and its .zip,
# from installer/Installer.swift. The installer holds no game code: it builds GJ Materia on the
# player's Mac from their own game (see installer/Installer.swift).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/installer"
APP="$OUT/GJ Materia Installer.app"
VERSION="${1:-1.0}"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for a in arm64 x86_64; do
  swiftc -O -target $a-apple-macos13.0 -o "$OUT/installer-$a" "$ROOT/installer/Installer.swift" 2>&1 | grep -v warning || true
  [ -x "$OUT/installer-$a" ] || { echo "swiftc failed ($a)"; exit 1; }
done
lipo -create "$OUT/installer-arm64" "$OUT/installer-x86_64" -output "$APP/Contents/MacOS/GJ Materia Installer"
rm -f "$OUT"/installer-*
cp "$ROOT/macos/icon/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>GJ Materia Installer</string>
  <key>CFBundleDisplayName</key><string>GJ Materia Installer</string>
  <key>CFBundleIdentifier</key><string>com.goodjoe.gjmateria.installer</string>
  <key>CFBundleExecutable</key><string>GJ Materia Installer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>GJ Materia by Good JOE. GPL v3.</string>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"        # ad-hoc: no Developer ID (right-click > Open the first time)
(cd "$OUT" && rm -f "GJ-Materia-Installer.zip" && ditto -c -k --keepParent "GJ Materia Installer.app" "GJ-Materia-Installer.zip")
echo "$APP"
echo "$OUT/GJ-Materia-Installer.zip"
