<p align="center"><img src="macos/icon/AppIcon-1024.png" width="200" alt="GJ Materia icon: a three-barrelled revolver before a red Meteor, VII behind it"></p>

<h1 align="center">GJ Materia</h1>

<p align="center"><b>FINAL FANTASY VII (Steam) as a native Mac app, with a 7th Heaven-style mod manager.</b><br>
by <a href="https://github.com/goodjoeth">Good JOE</a> · the macOS port of
<a href="https://github.com/bhuiyah/ff7-recomp-android">FF7Recomp</a></p>

> **This repository contains no game code or data.** You need your own copy of FINAL FANTASY VII
> from Steam. The build script translates **your** `ff7_en.exe` and compiles it on **your** Mac;
> nothing derived from the game is ever published. Do not share the built app: it contains code
> derived from the game. Not affiliated with or endorsed by Square Enix.

<p align="center">
  <img src="docs/images/mac/launcher-play.jpg" width="49%" alt="The launcher's Play page">
  <img src="docs/images/mac/launcher-mods.jpg" width="49%" alt="My mods: the enabled mods in priority order">
  <img src="docs/images/mac/launcher-catalog.jpg" width="49%" alt="Get mods: the 7th Heaven catalogs">
  <img src="docs/images/mac/launcher-settings.jpg" width="49%" alt="Settings">
</p>

[ภาษาไทยด้านล่าง](#ภาษาไทย)

## What you get

- The game runs natively: no Wine, no CrossOver. The game's code was statically recompiled to C;
  graphics are FFNx on Metal. On Apple silicon it is a native arm64 app (no Rosetta); on Intel
  Macs, an Intel app.
- A launcher in English or Thai: settings (4:3, 16:9, 16:10, **21:9**, resolution, 30/60/120 FPS, CRT filter,
  NTSC-J colours, controller rumble, game boosters), 7th Heaven catalogs with downloads, a mod
  library with 7th Heaven's Configure Mod (option previews), save import/export (PC saves,
  DuckStation / RetroArch / ePSXe memory cards), save states, achievements (offline set, and
  Steam achievements by QR sign-in), playing on any display (an AirPlay display used as a
  separate display, a TV, a second monitor).
- Keyboard and controllers (Xbox, PlayStation, MFi). With a controller the launcher switches to a
  TV mode (big tiles, D-pad and A/B); Select+Start held for 2 seconds (or Cmd+L) leaves the game
  for the launcher. F1 (or Select+Triangle) shows the achievements over the game; Cmd+Shift+A
  opens them in a window of their own.
- iCloud saves: saves and save states in iCloud Drive/FF7Recomp, so every Mac on the Apple ID
  continues the same game (a backup before each Play, and a warning when another Mac is playing).
- Report a problem: one .zip with the logs, settings and mod list (no game files, no Steam
  sign-in), to attach to a bug report.

## Screen shapes

The same spot on the world map in each shape the game can take. Widescreen shows more of the world
instead of stretching it (FFNx's widescreen, extended here to 21:9).

| 4:3 (original) | 16:9 | 21:9 |
|:---:|:---:|:---:|
| <img src="docs/images/mac/aspect-0.jpg" alt="4:3"> | <img src="docs/images/mac/aspect-2.jpg" alt="16:9"> | <img src="docs/images/mac/aspect-4.jpg" alt="21:9"> |

At 21:9 the mods' battle windows are laid out for 16:9; Settings chooses where the status window
(HP/MP) sits:

| Where 16:9 has it (default) | Halfway out | At the screen edge |
|:---:|:---:|:---:|
| <img src="docs/images/mac/hud21-0.jpg" alt="16:9 position"> | <img src="docs/images/mac/hud21-1.jpg" alt="halfway"> | <img src="docs/images/mac/hud21-2.jpg" alt="at the edge"> |

## Mods, side by side

The same saves with no mods, with one set and with another. Every mod comes from 7th Heaven's
catalogs and is installed from the launcher (Get mods > Download), with its options set in
My mods > Configure, as in 7th Heaven.

* **Vanilla**: no mods.
* **Set 1**: Finishing Touch, Enhanced Stock UI, Ninostyle Chibi (+ Fixes and Additions),
  Ninostyle Battle, SYW Unified Battle Textures, Cosmos Limit Break (widescreen field backgrounds).
* **Set 2**: Ninostyle HD (field models), Ninostyle Battle, Retextured World Textures, IFRIT
  interface tweaks, Wolfman avatars.

| Vanilla | Set 1 | Set 2 |
|:---:|:---:|:---:|
| <img src="docs/images/mac/mods-slums-vanilla.jpg" alt="slums vanilla"> | <img src="docs/images/mac/mods-slums-set1.jpg" alt="slums set1"> | <img src="docs/images/mac/mods-slums-set2.jpg" alt="slums set2"> |
| <img src="docs/images/mac/mods-shinra-vanilla.jpg" alt="shinra vanilla"> | <img src="docs/images/mac/mods-shinra-set1.jpg" alt="shinra set1"> | <img src="docs/images/mac/mods-shinra-set2.jpg" alt="shinra set2"> |
| <img src="docs/images/mac/mods-cosmo-vanilla.jpg" alt="cosmo vanilla"> | <img src="docs/images/mac/mods-cosmo-set1.jpg" alt="cosmo set1"> | <img src="docs/images/mac/mods-cosmo-set2.jpg" alt="cosmo set2"> |
| <img src="docs/images/mac/mods-nibel-vanilla.jpg" alt="nibel vanilla"> | <img src="docs/images/mac/mods-nibel-set1.jpg" alt="nibel set1"> | <img src="docs/images/mac/mods-nibel-set2.jpg" alt="nibel set2"> |

## Controller rumble

FINAL FANTASY VII on PC never vibrated, and FFNx's vibration covers FF8 only. GJ Materia adds it,
following what is on screen, on any controller the Mac can rumble (DualSense, DualShock 4, Xbox):

* **Battles**: a pulse on every hit, landed or taken, when its damage number comes up; strong
  magic, summons and Limit Breaks hit harder; a party member falling is a long, full rumble.
* **The field**: the screen's shakes (explosions, earthquakes, the plate falling) as strong as the
  shake, easing off when a scene leaves it running.
* **Minigames** (new, still being tuned): crashes, hits and landings in G-Bike, the chocobo races, snowboarding, Fort
  Condor, the submarine and the Speed Square, from their sound effects.
* Off, light or strong in Settings.

## Why it runs natively, and what that saves you

Wine, CrossOver, Whisky and the kits built on them run the Windows game as it is: every Windows
call goes through a re-implementation of Windows, Direct3D is translated to Metal on the fly
(often twice: Direct3D to Vulkan to Metal), and the 32-bit game needs Wine's 32-on-64-bit
bridge. That is where the stutters, freezes, black screens and broken movies come from, and
why each macOS or Wine update can break it.

GJ Materia does the translation once, ahead of time, on your Mac:

1. **The game's code becomes C.** A static recompiler (pcrecomp) reads your `ff7_en.exe` and
   writes every function of it as C source; clang compiles that into the app. Nothing is
   interpreted or emulated while you play.
2. **No Windows underneath.** The few Windows calls the game makes (files, timers, sound, input,
   windows) are answered by a small layer written for the Mac: files go straight to the disk,
   sound to Core Audio, controllers through Apple's Game Controller framework, the window is a
   normal Mac window.
3. **Graphics straight to Metal.** FFNx, the renderer the PC modding community uses, draws
   through bgfx's Metal backend: no Direct3D, no Vulkan, no translation layer.
4. **Mods without Windows.** 7th Heaven's catalogs, mod options and code patches (hext) are
   handled by the launcher itself; mods that patch the game's code can be lifted into the app too
   ("Make mods faster") so they run natively as well.

What that gives you: a steady 60 FPS with even frame pacing, no shader-translation hitches, quick
start-up, the Mac's own fullscreen, Retina resolution, rumble on Mac controllers, AirPlay to a TV,
iCloud saves, and nothing to configure (no bottles, prefixes or DLL overrides).

On Apple silicon the app is native arm64. The recompiled code expects the game's 32-bit memory
layout, which macOS keeps out of reach of arm64 apps (the lowest 4 GB), so GJ Materia gives the
game a 4 GB block of its own anywhere in memory and the code reaches it at an offset. Against the
earlier Intel build under Rosetta 2: the same steady 60 FPS, with about a fifth less CPU (30% vs
38% on a world-map walk). `FF7_ARCH=x86_64 bash tools/build_mac.sh` still builds the Intel app.

## First: your game files

You need FINAL FANTASY VII **bought on Steam** (the release sold today). Its files are the Windows
version; get them onto the Mac one of these ways:

- **A Windows PC:** Steam > right-click the game > Manage > Browse local files, and copy the
  whole `FINAL FANTASY VII Steam Edition` folder (about 3.5 GB) to the Mac (Downloads or an
  external drive is fine).
- **CrossOver or Whisky on the Mac:** install Windows Steam in a bottle, then FF7.
- **steamcmd on the Mac** (Valve's command-line Steam; it asks for your password and Steam Guard
  code in the Terminal):
  ```bash
  mkdir -p ~/steamcmd && cd ~/steamcmd
  curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz" | tar zxf -
  ./steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir ~/FF7 +login YOUR_STEAM_LOGIN +app_update 3837340 validate +quit
  ```

The build script and the launcher find the folder by themselves in all of these places (and on
external drives); you can also point them at it.

## Install (the easy way)

1. Get your game files (above).
2. Download **GJ-Materia-Installer.zip** from [Releases](https://github.com/goodjoeth/gj-materia/releases),
   unzip it, and open **GJ Materia Installer**. The first time, macOS may say it can't check the
   developer: right-click the installer, choose **Open**, then **Open** again.
3. Press **Install**. It sets up Apple's Command Line Tools if missing (macOS asks you to
   confirm), fetches the build tools into its own folder (no Homebrew needed), finds your
   game, downloads this source and builds GJ Materia on your Mac (20-40 minutes the first time),
   then puts it in Applications.

The installer contains no game code and downloads none: the game's code is translated from your
own copy, on your Mac. Use the Mac's own drive or one formatted APFS / Mac OS Extended (exFAT
drives don't work for the build); about 15 GB free.

## Build (by hand)

Needs macOS 13 or later, about 15 GB free and 20-30 minutes the first time.

1. Get your game files (above).
2. Install the tools:
   ```bash
   xcode-select --install
   brew install cmake ninja
   python3 -m pip install --user capstone
   ```
3. Get this source and build:
   ```bash
   git clone https://github.com/goodjoeth/gj-materia.git
   cd gj-materia
   bash tools/build_mac.sh            # finds the game; or pass its folder
   ```
4. Open `build/macos/GJ Materia.app`. On the Play page, **Find FF7 on this Mac** and **Import**
   (once: the game files are copied into the app's folder), then **Play**.

Keep the source folder: **My mods > Make mods faster** re-lifts the enabled mods' code patches
from it (about 5-10 minutes) so they run natively.

Technical notes: [docs/MACOS.md](docs/MACOS.md). The Android version this is ported from:
[README_ANDROID.md](README_ANDROID.md).

## Roadmap

Done: everything listed under "What you get". Planned next, roughly in order:

* **More rumble**: a heartbeat at low HP, a pulse when a Limit Break is ready, patterns per
  element (fire crackle, thunder bursts, quake rumble), summons timed to their animations, the
  airship's and buggy's engines; DualSense light bar (party HP, Limit ready) and adaptive triggers.
* **Smoother scene changes**: load the next scene's files ahead (the last 50-150 ms hitches are
  file reads).
* **All mod code native**: the remaining code patches that still run in the interpreter.
* **21:9 battle windows without UI mods** (the game's own layout).
* **Updates from the app**: tell when a new GJ Materia is out and rebuild it with the installer.
* **A signed installer** (Apple Developer ID, so no right-click > Open the first time).
* **iPad and iPhone**: an app for sideloading (AltStore, SideStore, LiveContainer), built on the
  native Apple silicon version (done).
* **RetroAchievements online**, once RetroAchievements approves the app (the set works offline now).

Help and bug reports are welcome: the launcher's "Report a problem..." makes a .zip to attach.

## Thanks and credits

**A word from Good JOE.** I had given up on playing a modded FINAL FANTASY VII on my Mac: Wine and
CrossOver stuttered, froze and broke with every update. Then I found
[**FF7Recomp** by bhuiyah](https://github.com/bhuiyah/ff7-recomp-android), a static recompilation
of the PC game for Android. It showed me the game could run natively, without emulating Windows,
and that is what made me see a way to bring it to the Mac. GJ Materia is built on that work. Thank
you, bhuiyah.

None of this would exist without the people who have kept FF7 on PC alive for years:

* **[FF7Recomp](https://github.com/bhuiyah/ff7-recomp-android)** by bhuiyah: the recompiled game,
  its runtime and the Android port this Mac version grew from.
* **[FFNx](https://github.com/julianxhokaxhiu/FFNx)** by Julian Xhokaxhiu and its contributors: the
  renderer and the heart of modern FF7 on PC (widescreen, 60 FPS, mod textures, music, achievements).
* **[7th Heaven](https://github.com/tsunamods-codes/7th-Heaven)** by the Tsunamods team: the mod
  manager whose catalogs, mod format, options and code patches the launcher follows.
* **[pcrecomp](https://github.com/sp00nznet/pcrecomp)** by sp00nznet: the static recompiler.
* **The Qhimm and Tsunamods communities and every mod author**, among them Bonez (Finishing
  Touch), Chrysalis (Enhanced Stock UI), Ninostyle, Satsuki Yatoshi (SYW), KWRRK (IFRIT), the Cosmos
  team and the rest of the catalog's authors. Please support them.
* **The libraries**: bgfx (Branimir Karadžić), FFmpeg, SDL, rcheevos, capstone and the others in
  `tools/fetch_deps*.sh`.
* **Square Enix**, for FINAL FANTASY VII. Buy the game on Steam.

GJ Materia was put together by Good JOE, with an AI coding agent (Claude, in Claude Code) writing
the code under his direction, as FF7Recomp's Android version was. Licensed under the GNU GPL v3
(see LICENSE), as FF7Recomp and FFNx.

---

## ภาษาไทย

FINAL FANTASY VII (เวอร์ชัน Steam) เป็นแอป Mac แบบ native พร้อมตัวจัดการม็อดแบบ 7th Heaven

> **repo นี้ไม่มีโค้ดหรือไฟล์ของเกม** ต้องมี FINAL FANTASY VII จาก Steam ของตัวเอง สคริปต์จะแปลง
> `ff7_en.exe` **ของคุณ** และ compile บน Mac **ของคุณ** เท่านั้น **ห้ามแชร์แอปที่ build แล้ว** เพราะมีโค้ดที่แปลงมาจากเกม
> ไม่เกี่ยวข้องกับ Square Enix

### ได้อะไร
- เกมรันแบบ native ไม่ใช้ Wine/CrossOver (โค้ดเกมถูกแปลงเป็น C ภาพผ่าน FFNx บน Metal บน Apple silicon เป็นแอป arm64 แท้ ไม่ใช้ Rosetta บน Mac Intel เป็นแอป Intel)
- Launcher ภาษาอังกฤษหรือไทย (เปลี่ยนได้ในหน้าตั้งค่า): ตั้งค่า (4:3, 16:9, 16:10, **21:9**, ความละเอียด, 30/60/120 FPS, ฟิลเตอร์ CRT, สี NTSC-J, การสั่นของจอย, ตัวช่วยเล่น), ค้นหาและดาวน์โหลดม็อดจาก catalog ของ 7th Heaven, จัดการม็อดพร้อมภาพตัวอย่างตัวเลือก, นำเข้า/ส่งออกเซฟ (PC, memory card ของ DuckStation/RetroArch/ePSXe), save state, achievement (ออฟไลน์ และ Steam ผ่าน QR), เลือกจอที่เล่น (รวม AirPlay แบบจอแยก)
- คีย์บอร์ดและจอย Xbox / PlayStation / MFi กดปุ่มจอยใน launcher จะเข้าโหมดทีวี (ใช้จอยล้วน) กด Select+Start ค้าง 2 วินาที (หรือ Cmd+L) ในเกมเพื่อกลับ launcher กด F1 (หรือ Select+△) ดู achievement ทับบนเกม หรือ Cmd+Shift+A เปิดเป็นหน้าต่างแยก
- เซฟ iCloud: เก็บเซฟและ save state ใน iCloud Drive/FF7Recomp ทุก Mac ที่ใช้ Apple ID เดียวกันเล่นต่อกันได้ (สำรองเซฟทุกครั้งที่กดเล่น และเตือนเมื่อมีอีกเครื่องเปิดเกมอยู่)
- ปุ่มรายงานปัญหา: รวม log ตั้งค่า และรายการม็อดเป็นไฟล์ .zip เดียว (ไม่มีไฟล์เกมและข้อมูลบัญชี Steam)

### ทำไมถึงเป็น native และช่วยลดปัญหาอะไรจากการใช้ Wine / CrossOver
Wine, CrossOver, Whisky และชุดที่สร้างบนพวกนี้ รันเกม Windows ตามเดิม ทุกคำสั่งของ Windows ต้องผ่านตัวจำลอง Windows, Direct3D ถูกแปลงเป็น Metal ระหว่างเล่น (หลายครั้งแปลงสองชั้น Direct3D → Vulkan → Metal) และเกม 32 บิตต้องผ่านสะพาน 32-on-64 ของ Wine จึงเกิดอาการกระตุก ค้าง จอดำ ภาพยนตร์ในเกมไม่เล่น และพังได้ทุกครั้งที่อัปเดต macOS หรือ Wine

GJ Materia แปลงครั้งเดียวล่วงหน้าบน Mac ของคุณ:
1. **โค้ดเกมกลายเป็นภาษา C** ตัว static recompiler อ่าน `ff7_en.exe` ของคุณแล้วเขียนทุกฟังก์ชันออกมาเป็นซอร์ส C แล้ว compile เข้าแอป ระหว่างเล่นไม่มีการจำลองหรือแปลโค้ด
2. **ไม่มี Windows อยู่ข้างใต้** คำสั่ง Windows ไม่กี่อย่างที่เกมใช้ (ไฟล์ เวลา เสียง จอย หน้าต่าง) ตอบด้วยโค้ดที่เขียนสำหรับ Mac โดยตรง: เสียงไป Core Audio, จอยผ่าน Game Controller ของ Apple, หน้าต่างเป็นหน้าต่าง Mac ปกติ
3. **ภาพส่งตรงไป Metal** ผ่าน FFNx (ตัว render ที่ชุมชนม็อด PC ใช้) บน bgfx Metal ไม่มี Direct3D ไม่มี Vulkan ไม่มีชั้นแปลง
4. **ม็อดไม่ต้องพึ่ง Windows** launcher จัดการ catalog ตัวเลือก และ code patch (hext) ของ 7th Heaven เอง ม็อดที่แก้โค้ดเกมก็ lift เข้าแอปให้รันแบบ native ได้ ("ทำให้ม็อดเร็วขึ้น")

ผลที่ได้: 60 FPS นิ่ง จังหวะเฟรมสม่ำเสมอ ไม่กระตุกจากการแปลง shader เปิดเร็ว เต็มจอแบบ Mac ความละเอียด Retina จอยสั่นได้ AirPlay ขึ้นทีวี เซฟ iCloud และไม่ต้องตั้งค่า bottle, prefix หรือ DLL ใดๆ

บน Apple silicon แอปเป็น arm64 แท้: โค้ดที่แปลงมาต้องใช้หน่วยความจำแบบ 32 บิตของเกม ซึ่ง macOS ไม่ให้แอป arm64 ใช้ช่วง 4 GB ล่างสุด GJ Materia จึงจองพื้นที่ 4 GB ให้เกมไว้ที่อื่นแล้วให้โค้ดเข้าถึงแบบเลื่อนตำแหน่ง เทียบกับเวอร์ชัน Intel ที่รันผ่าน Rosetta 2 เดิม: 60 FPS นิ่งเท่าเดิม แต่ใช้ CPU น้อยลงราวหนึ่งในห้า (30% เทียบ 38% ตอนเดินบน world map) ถ้าต้องการแอป Intel ใช้ `FF7_ARCH=x86_64 bash tools/build_mac.sh`

### เปรียบเทียบสัดส่วนจอและตำแหน่ง HUD
ภาพด้านบน (หัวข้อ Screen shapes): world map จุดเดียวกันที่ 4:3, 16:9 และ 21:9 (จอกว้างเห็นโลกมากขึ้น ไม่ได้ยืดภาพ) และฉากต่อสู้ที่ 21:9 กับตำแหน่งแถบ HP/MP สามแบบที่เลือกได้ในหน้าตั้งค่า

### ม็อดเทียบกัน และจอยสั่น
ภาพเทียบด้านบน (หัวข้อ Mods, side by side): เซฟเดียวกันแบบไม่มีม็อด, ม็อดชุดที่ 1 และชุดที่ 2 ทุกม็อดโหลดจาก catalog ของ 7th Heaven ผ่าน launcher

**จอยสั่น (จุดเด่น):** FF7 เวอร์ชัน PC ไม่เคยมีจอยสั่น และ FFNx ทำไว้ให้เฉพาะ FF8 GJ Materia เพิ่มให้ตามสิ่งที่เกิดบนจอ ใช้ได้กับจอยที่สั่นบน Mac (DualSense, DualShock 4, Xbox): ตีโดนหรือโดนตีสั่นทุกครั้ง เวทแรง/อัญเชิญ/Limit Break สั่นหนักกว่า สมาชิกล้มสั่นยาว ฉากสั่น (ระเบิด แผ่นดินไหว) สั่นตามความแรง และมินิเกม (ใหม่ ยังปรับจูนอยู่: G-Bike แข่งช็อกโกโบ สโนว์บอร์ด Fort Condor เรือดำน้ำ Speed Square) สั่นตามเสียงชนและกระแทก ปรับ ปิด/เบา/แรง ได้

### แผนงานต่อไป (Roadmap)
- **จอยสั่นเพิ่ม**: หัวใจเต้นตอน HP ต่ำ, สั่นตอน Limit พร้อม, รูปแบบตามธาตุ (ไฟ สายฟ้า แผ่นดินไหว), อัญเชิญสั่นตามจังหวะแอนิเมชัน, เสียงเครื่องยนต์เรือเหาะ/รถบั๊กกี้ และไฟ DualSense ตาม HP / Limit กับ adaptive trigger
- **เปลี่ยนฉากลื่นขึ้น**: โหลดไฟล์ฉากถัดไปล่วงหน้า
- **โค้ดม็อดรัน native ทั้งหมด**
- **UI ฉากต่อสู้ 21:9 สำหรับ UI เดิมของเกม** (ไม่มีม็อด)
- **อัปเดตจากในแอป**: แจ้งเมื่อมีเวอร์ชันใหม่และ build ใหม่ผ่าน installer
- **installer ที่ลงชื่อกับ Apple** (ไม่ต้องคลิกขวา → Open ครั้งแรก)
- **iPad และ iPhone**: แอปสำหรับ sideload (AltStore, SideStore, LiveContainer) ต่อยอดจากเวอร์ชัน Apple silicon แบบ native (ทำเสร็จแล้ว)
- **RetroAchievements ออนไลน์** เมื่อ RetroAchievements อนุมัติ

### ขอบคุณและเครดิต
**จาก Good JOE:** ผมเคยหมดหวังกับการเล่น FINAL FANTASY VII แบบลงม็อดบน Mac ไปแล้ว เพราะ Wine และ CrossOver ทั้งกระตุก ทั้งค้าง และพังทุกครั้งที่อัปเดต จนได้เจอ [**FF7Recomp** ของ bhuiyah](https://github.com/bhuiyah/ff7-recomp-android) ที่แปลงเกมเวอร์ชัน PC ให้รันบน Android ได้โดยตรง มันทำให้ผมเห็นว่าเกมนี้รันแบบ native ได้โดยไม่ต้องจำลอง Windows และเป็นแรงบันดาลใจที่ทำให้ผมมองเห็นโอกาสที่จะทำให้เล่นบน Mac ได้ GJ Materia สร้างต่อจากงานนั้น ขอบคุณ bhuiyah มากครับ

และขอบคุณทุกคนที่ทำให้ FF7 บน PC ยังมีชีวิตมาจนทุกวันนี้:
- **FF7Recomp** (bhuiyah): เกมที่แปลงโค้ดแล้ว ตัว runtime และเวอร์ชัน Android ที่เป็นต้นทางของเวอร์ชัน Mac
- **FFNx** (Julian Xhokaxhiu และทีม): ตัว render และหัวใจของ FF7 บน PC ยุคใหม่ (จอกว้าง 60 FPS texture ม็อด เพลง achievement)
- **7th Heaven** (ทีม Tsunamods): ตัวจัดการม็อดที่ launcher ของเราใช้ catalog รูปแบบม็อด ตัวเลือก และ code patch ตามแบบ
- **pcrecomp** (sp00nznet): ตัวแปลงโค้ดเกม (static recompiler)
- **ชุมชน Qhimm, Tsunamods และผู้สร้างม็อดทุกคน** เช่น Bonez (Finishing Touch), Chrysalis (Enhanced Stock UI), Ninostyle, Satsuki Yatoshi (SYW), KWRRK (IFRIT), ทีม Cosmos และทุกคนใน catalog ฝากสนับสนุนพวกเขาด้วย
- **ไลบรารี**: bgfx, FFmpeg, SDL, rcheevos, capstone และอื่นๆ
- **Square Enix** ผู้สร้าง FINAL FANTASY VII ซื้อเกมบน Steam เพื่อสนับสนุน

### ขั้นแรก: ไฟล์เกมของคุณ (ต้องทำก่อน)
ต้องซื้อ FINAL FANTASY VII **บน Steam** (เวอร์ชันที่ขายปัจจุบัน) ไฟล์เกมเป็นเวอร์ชัน Windows เอามาไว้ใน Mac ได้ 3 วิธี:
- **มีคอม Windows:** ใน Steam คลิกขวาที่เกม → Manage → Browse local files → ก๊อปโฟลเดอร์ `FINAL FANTASY VII Steam Edition` ทั้งโฟลเดอร์ (~3.5 GB) มาไว้ใน Mac
- **CrossOver หรือ Whisky บน Mac:** ติดตั้ง Steam เวอร์ชัน Windows ใน bottle แล้วติดตั้ง FF7
- **steamcmd บน Mac:** ใช้คำสั่งในส่วนภาษาอังกฤษด้านบน (Terminal จะถามรหัสผ่านและรหัส Steam Guard)

สคริปต์ build และ launcher จะค้นหาโฟลเดอร์เกมเองทุกที่ข้างบน รวมถึงไดรฟ์ภายนอก

### ติดตั้งแบบง่าย
1. เตรียมไฟล์เกม (ขั้นแรกด้านบน)
2. โหลด **GJ-Materia-Installer.zip** จากหน้า [Releases](https://github.com/goodjoeth/gj-materia/releases) แตกไฟล์แล้วเปิด **GJ Materia Installer** (ครั้งแรก macOS อาจเตือนว่าไม่รู้จักผู้พัฒนา ให้คลิกขวาที่ตัวติดตั้ง → Open → Open)
3. กด **ติดตั้ง** ตัวติดตั้งจะลง Command Line Tools ให้ถ้ายังไม่มี (macOS จะถามยืนยัน) โหลดเครื่องมือ build มาเก็บเอง (ไม่ต้องใช้ Homebrew) หาเกมให้ โหลดซอร์ส แล้ว build GJ Materia บน Mac ของคุณ (ครั้งแรก 20–40 นาที) แล้ววางไว้ใน Applications

ตัวติดตั้งไม่มีโค้ดเกมและไม่ได้โหลดโค้ดเกมมา โค้ดเกมถูกแปลงจากเกมของคุณเองบนเครื่องคุณ ใช้ไดรฟ์ในเครื่อง หรือไดรฟ์ที่ฟอร์แมตเป็น APFS / Mac OS Extended (ไดรฟ์ exFAT ใช้ build ไม่ได้) พื้นที่ว่างประมาณ 15 GB

### วิธี build (ทำเอง)
ต้องใช้ macOS 13 ขึ้นไป พื้นที่ว่าง ~15 GB ครั้งแรกใช้เวลา 20–30 นาที

1. เตรียมไฟล์เกม (ขั้นแรกด้านบน)
2. ติดตั้งเครื่องมือ (คำสั่งในส่วนภาษาอังกฤษด้านบน)
3. โหลดซอร์สแล้วรัน `bash tools/build_mac.sh` (ค้นหาเกมเอง หรือใส่ path ของโฟลเดอร์เกมต่อท้าย)
4. เปิด `build/macos/GJ Materia.app` → หน้าเล่น → **ค้นหา FF7 ในเครื่อง** → **นำเข้า** (ครั้งเดียว) → **เล่น**

เก็บโฟลเดอร์ซอร์สไว้ด้วย: ปุ่ม **ม็อดของฉัน → ทำให้ม็อดเร็วขึ้น** จะใช้มัน lift โค้ดของม็อดให้รันแบบ native
