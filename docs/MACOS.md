# FF7Recomp on macOS

x86_64 build run by Rosetta 2: the lifted code uses the game's own 32-bit addresses
(RECOMP_FLAT_MEMORY), and only x86_64 processes may map below 4 GB on macOS. The app is linked
non-PIE with a zerofill segment reserving [0x10000, 0x80000000) for the guest (src/mac/).

## Build (once)

    bash tools/setup_mac.sh            # pinned toolkits + patches + FFNx edits
    bash tools/fetch_deps_mac.sh       # FFNx's libraries
    python3 -I tools/import_game.py "<FINAL FANTASY VII Steam Edition>"
    # lift (see tools/run_lift.py; PYTHONPATH=external/deps/pefile), then:
    bash tools/build_ffmpeg_mac.sh
    bash tools/compile_shaders_mac.sh
    cmake -S macos -B build/macos -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
    cmake --build build/macos
    bash tools/stage_game_mac.sh       # ~/Library/Application Support/FF7Recomp/game

Run: `open build/macos/FF7Recomp.app`. Log: `~/Library/Application Support/FF7Recomp/ff7.log`.
`FF7_QUICKBOOT=newgame` (running the binary directly) goes straight to a new game.

## Launcher

The app opens a SwiftUI launcher first (src/mac/launcher): Play (start at the title, a new game
or the latest save), Settings (written into game/FFNx.toml from FFNx.template.toml at each Play,
plus the enabled mods' FFNxConfig), My mods (enable, drag to order, mod.xml options, conflicts,
add .7z/.iro/.zip by file or drag and drop), Get mods (the 7th Heaven Qhimm and Sega catalogs:
search, category, preview, download with progress, install, update) and Controls.
At each Play it also writes fixes/data/lang-*/kernel/window.bin (m, M, w, W back to 11 pixels
wide, as the Android launcher does) and lists that folder last in the profile.
FF7_QUICKBOOT / FF7_NO_LAUNCHER skip the launcher (tests).

More panes: Downloads (progress, speed, history) and Saves (PC saves list / import / export,
PlayStation memory cards in and out, save-state slots). The game window follows live resize and
full screen (tools/ffnx_edit_mac.py: FFNx's WM_SIZE path), NTSC-J colours need the glut_*.png LUTs
in game/shaders (tools/stage_game_mac.sh), and rumble goes to the first controller with haptics
(CoreHaptics; src/ffnx_port/rumble.cpp decides when).

For iPad later: Core.swift, Mods.swift and Saves.swift use Foundation only (gzip through the
Compression framework, no external tools; .zip mods are the one macOS-only path). Views.swift uses
fileImporter / fileExporter / openURL; HSplitView, VSplitView and Table there are macOS layouts
that an iPad build would swap for NavigationSplitView and List.

## Mods from the command line

`python3 tools/ff7mod_mac.py install <mod.7z|mod.iro|folder>`, then `list`, `enable`, `disable`,
`up`, `down`, `option`, `remove`. The .7z extractor is built with:

    L=external/deps/lzma; clang -O2 -include src/mac/include/mac_compat.h -o build/tools/ff7mod-un7z \
      src/mac/ff7mod_un7z_main.c src/android/un7z.c $L/7z*.c $L/Bcj2.c $L/Bra*.c $L/CpuArch.c \
      $L/Delta.c $L/Lzma2Dec.c $L/LzmaDec.c -I$L

## 21:9

aspect_ratio = 4 is an FF7Recomp mode (tools/ffnx_edit_mac.py), made the way FFNx makes 16:10: the
widescreen viewport is 1138x480 (64:27) with wide_viewport_x = -249, which every FFNx widescreen
patch reads. Fields wide enough for 16:9 extend as far as their background goes (centred); the
camera clamp's half extension follows the viewport. Its code writes are in
config/ffnx_manifests/ffnx_manifest_l*_ar4.json (collected with FF7_WATCHDOG + FF7_FFNX_MANIFEST,
one run per FPS mode), so the re-lift has native variants for them. The 21:9 viewport is set at
the start of ff7_widescreen_hook_init too: FFNx bakes values such as the skybox width and battle
UI offsets into the game's code there, before Widescreen::init runs (with 854 they were half
16:9, half 21:9: black sky corners, overlapping battle HUD). Mods see aspect_ratio 4 as 2
(src/mods/mods.cpp), so UI mods choose their 16:9 layouts.

The launcher's "play on" display picker lists every screen macOS has, including an AirPlay
display used as a separate display (not mirrored); the game window opens there.

## Achievements

The offline set (src/ffnx_port/achievements.cpp, RetroAchievements' format) runs as on Android;
the launcher's Achievements page lists it. Online RetroAchievements needs RA's approval of this
client first. Steam achievements on Android go through JavaSteam (src/android SteamLink.java +
src/ffnx_port/steam_android.cpp's files/steam/state.txt and pending.txt). On macOS the launcher does
the same in Swift (src/mac/launcher/Steam.swift): Steam's client protocol over WebSocket to a CM
server, QR sign-in (Authentication.BeginAuthSessionViaQR / PollAuthSessionStatus), ClientLogon with
the refresh token (kept in the Keychain), ClientGetUserStats / ClientStoreUserStats2 with the
schema's achievement bits. It syncs when the launcher opens and every minute while the game runs.

## Finding slow frames

`FF7_PERF=1` prints frames per second and the slowest frames every 10 s. `FF7_HITCH=1` samples
the game thread's stack every millisecond and, for each frame over 40 ms, prints where those
samples were: system and FFNx functions by name, the rest as addresses for
`atos -o build/macos/FF7Recomp.app/Contents/MacOS/FF7Recomp -arch x86_64 <address>`.
Scene changes used to spend most of a 100-250 ms hitch converting the game's textures and
decoding mod PNGs (bimg's lodepng); `tools/ffnx_edit_mac.py` now gives FFNx a table-driven
conversion and decodes PNGs with libpng. What is left is mostly reading files.
