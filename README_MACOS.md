# FF7Recomp for Mac

FINAL FANTASY VII (the Steam release) as a native Mac app, with a 7th Heaven-style mod manager.
The macOS port of [FF7Recomp](https://github.com/bhuiyah/ff7-recomp-android).

> **This repository contains no game code or data.** You need your own copy of FINAL FANTASY VII
> from Steam. The build script translates **your** `ff7_en.exe` and compiles it on **your** Mac;
> nothing derived from the game is ever published. Do not share the built app: it contains code
> derived from the game. Not affiliated with or endorsed by Square Enix.

[ภาษาไทยด้านล่าง](#ภาษาไทย)

## What you get

- The game runs natively: no Wine, no CrossOver. The game's code was statically recompiled to C;
  graphics are FFNx on Metal. (It is built as an Intel app and runs under Rosetta 2 on Apple
  silicon: the recompiled code keeps the game's 32-bit memory layout, which only Intel processes
  may use on macOS.)
- A launcher: settings (4:3, 16:9, 16:10, **21:9**, resolution, 30/60/120 FPS, CRT filter,
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

## Build

Needs macOS 13 or later, about 15 GB free and 20-30 minutes the first time.

1. Get your game files (above).
2. Install the tools:
   ```bash
   xcode-select --install
   brew install cmake ninja
   python3 -m pip install --user capstone
   softwareupdate --install-rosetta --agree-to-license   # Apple silicon
   ```
3. Get this source and build:
   ```bash
   git clone -b macos <this repository> ff7recomp-mac
   cd ff7recomp-mac
   bash tools/build_mac.sh            # finds the game; or pass its folder
   ```
4. Open `build/macos/FF7Recomp.app`. On the Play page, **Find FF7 on this Mac** and **Import**
   (once: the game files are copied into the app's folder), then **Play**.

Keep the source folder: **My mods > Make mods faster** re-lifts the enabled mods' code patches
from it (about 5-10 minutes) so they run natively.

Technical notes: [docs/MACOS.md](docs/MACOS.md).

## Credits

FF7Recomp and its Android port; [FFNx](https://github.com/julianxhokaxhiu/FFNx);
[pcrecomp](https://github.com/sp00nznet/pcrecomp); 7th Heaven and the Qhimm / Tsunamods
catalogs; bgfx, FFmpeg, SDL, rcheevos and the other libraries in `tools/fetch_deps*.sh`; and every
mod author. Please support them. Licensed under the GNU GPL v3 (see LICENSE), as FF7Recomp and FFNx.

---

## ภาษาไทย

FINAL FANTASY VII (เวอร์ชัน Steam) เป็นแอป Mac แบบ native พร้อมตัวจัดการม็อดแบบ 7th Heaven

> **repo นี้ไม่มีโค้ดหรือไฟล์ของเกม** ต้องมี FINAL FANTASY VII จาก Steam ของตัวเอง สคริปต์จะแปลง
> `ff7_en.exe` **ของคุณ** และ compile บน Mac **ของคุณ** เท่านั้น **ห้ามแชร์แอปที่ build แล้ว** เพราะมีโค้ดที่แปลงมาจากเกม
> ไม่เกี่ยวข้องกับ Square Enix

### ได้อะไร
- เกมรันแบบ native ไม่ใช้ Wine/CrossOver (โค้ดเกมถูกแปลงเป็น C ภาพผ่าน FFNx บน Metal แอปเป็น Intel และรันผ่าน Rosetta 2 บน Apple silicon)
- Launcher ภาษาไทย: ตั้งค่า (4:3, 16:9, 16:10, **21:9**, ความละเอียด, 30/60/120 FPS, ฟิลเตอร์ CRT, สี NTSC-J, การสั่นของจอย, ตัวช่วยเล่น), ค้นหาและดาวน์โหลดม็อดจาก catalog ของ 7th Heaven, จัดการม็อดพร้อมภาพตัวอย่างตัวเลือก, นำเข้า/ส่งออกเซฟ (PC, memory card ของ DuckStation/RetroArch/ePSXe), save state, achievement (ออฟไลน์ และ Steam ผ่าน QR), เลือกจอที่เล่น (รวม AirPlay แบบจอแยก)
- คีย์บอร์ดและจอย Xbox / PlayStation / MFi กดปุ่มจอยใน launcher จะเข้าโหมดทีวี (ใช้จอยล้วน) กด Select+Start ค้าง 2 วินาที (หรือ Cmd+L) ในเกมเพื่อกลับ launcher กด F1 (หรือ Select+△) ดู achievement ทับบนเกม หรือ Cmd+Shift+A เปิดเป็นหน้าต่างแยก
- เซฟ iCloud: เก็บเซฟและ save state ใน iCloud Drive/FF7Recomp ทุก Mac ที่ใช้ Apple ID เดียวกันเล่นต่อกันได้ (สำรองเซฟทุกครั้งที่กดเล่น และเตือนเมื่อมีอีกเครื่องเปิดเกมอยู่)
- ปุ่มรายงานปัญหา: รวม log ตั้งค่า และรายการม็อดเป็นไฟล์ .zip เดียว (ไม่มีไฟล์เกมและข้อมูลบัญชี Steam)

### ขั้นแรก: ไฟล์เกมของคุณ (ต้องทำก่อน)
ต้องซื้อ FINAL FANTASY VII **บน Steam** (เวอร์ชันที่ขายปัจจุบัน) ไฟล์เกมเป็นเวอร์ชัน Windows เอามาไว้ใน Mac ได้ 3 วิธี:
- **มีคอม Windows:** ใน Steam คลิกขวาที่เกม → Manage → Browse local files → ก๊อปโฟลเดอร์ `FINAL FANTASY VII Steam Edition` ทั้งโฟลเดอร์ (~3.5 GB) มาไว้ใน Mac
- **CrossOver หรือ Whisky บน Mac:** ติดตั้ง Steam เวอร์ชัน Windows ใน bottle แล้วติดตั้ง FF7
- **steamcmd บน Mac:** ใช้คำสั่งในส่วนภาษาอังกฤษด้านบน (Terminal จะถามรหัสผ่านและรหัส Steam Guard)

สคริปต์ build และ launcher จะค้นหาโฟลเดอร์เกมเองทุกที่ข้างบน รวมถึงไดรฟ์ภายนอก

### วิธี build
ต้องใช้ macOS 13 ขึ้นไป พื้นที่ว่าง ~15 GB ครั้งแรกใช้เวลา 20–30 นาที

1. เตรียมไฟล์เกม (ขั้นแรกด้านบน)
2. ติดตั้งเครื่องมือ (คำสั่งในส่วนภาษาอังกฤษด้านบน)
3. โหลดซอร์สแล้วรัน `bash tools/build_mac.sh` (ค้นหาเกมเอง หรือใส่ path ของโฟลเดอร์เกมต่อท้าย)
4. เปิด `build/macos/FF7Recomp.app` → หน้าเล่น → **ค้นหา FF7 ในเครื่อง** → **นำเข้า** (ครั้งเดียว) → **เล่น**

เก็บโฟลเดอร์ซอร์สไว้ด้วย: ปุ่ม **ม็อดของฉัน → ทำให้ม็อดเร็วขึ้น** จะใช้มัน lift โค้ดของม็อดให้รันแบบ native
