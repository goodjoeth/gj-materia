#!/usr/bin/env bash
# build_mac.sh - FF7Recomp for macOS from a fresh clone, in one command, from YOUR OWN copy of
# FINAL FANTASY VII (the Steam release). Nothing derived from the game leaves this Mac: the
# game's code is translated and compiled here, into build/macos/FF7Recomp.app.
#
# usage: bash tools/build_mac.sh "/path/to/FINAL FANTASY VII Steam Edition"
#
# Needs: macOS 13+, Xcode or the Command Line Tools (xcode-select --install), Homebrew's cmake and
# ninja (brew install cmake ninja), Python 3 with capstone (python3 -m pip install --user capstone).
# Takes about 15-30 minutes the first time; re-running carries on where it stopped.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

GAME="${1:-}"
[ -n "$GAME" ] || { [ -f game/ff7_en.exe ] || die "usage: bash tools/build_mac.sh \"/path/to/FINAL FANTASY VII Steam Edition\""; }

step "1/8 checking the tools"
xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools are missing: run  xcode-select --install"
command -v cmake >/dev/null || die "cmake is missing: brew install cmake"
command -v ninja >/dev/null || die "ninja is missing: brew install ninja"
command -v python3 >/dev/null || die "python3 is missing"
python3 -c 'import capstone' 2>/dev/null || die "Python's capstone is missing: python3 -m pip install --user capstone"
[ "$(uname -m)" = arm64 ] && { arch -x86_64 /usr/bin/true 2>/dev/null || die "Rosetta 2 is missing: softwareupdate --install-rosetta --agree-to-license"; }
echo "ok"

step "2/8 toolkits and libraries (pinned, patched)"
[ -d external/FFNx/.git ] && [ -f external/.setup-mac-done ] || { bash tools/setup_mac.sh; touch external/.setup-mac-done; }
bash tools/fetch_deps_mac.sh | tail -1

step "3/8 your game files"
if [ -n "$GAME" ]; then python3 -I tools/import_game.py "$GAME"; fi
python3 -I tools/check_inputs.py | tail -1

step "4/8 translating the game's code (the lift)"
[ -f generated/recomp/recomp_dispatch.c ] || bash tools/lift_mac.sh

step "5/8 FFmpeg (movies)"
[ -f build/ffmpeg-mac/lib/libavcodec.a ] || bash tools/build_ffmpeg_mac.sh | tail -1

step "6/8 shaders (bgfx shaderc, Metal)"
if [ ! -x external/bgfx/.build/osx-arm64/bin/shadercRelease ] && [ ! -x external/bgfx/.build/osx-x64/bin/shadercRelease ]; then
  (cd external/bgfx && xattr -d com.apple.quarantine ../bx/tools/bin/darwin/genie 2>/dev/null || true
   ../bx/tools/bin/darwin/genie --with-tools --gcc=osx-arm64 gmake >/dev/null
   make -C .build/projects/gmake-osx-arm64 config=release shaderc -j"$(sysctl -n hw.ncpu)" >/dev/null)
fi
[ -f build/shaders-mtl/FFNx.flat.mtl.frag ] || bash tools/compile_shaders_mac.sh | tail -1

step "7/8 compiling the app (the first time takes a while)"
cmake -S macos -B build/macos -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null
cmake --build build/macos -- -j"$(sysctl -n hw.ncpu)" | grep -E ' error|FAILED' && die "the build failed (see above)" || true
[ -x build/macos/FF7Recomp.app/Contents/MacOS/FF7Recomp ] || die "the build failed"

step "8/8 done"
echo "App: $ROOT/build/macos/FF7Recomp.app"
echo "Open it, then in the launcher: Play > Import from your FF7 folder (once), and Play."
echo "Run it with:  open \"$ROOT/build/macos/FF7Recomp.app\""
echo "(You can drag the app into /Applications; keep this folder for mod re-lifts.)"
