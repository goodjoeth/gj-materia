# FF7Recomp for macOS: the lifted game, its runtime, FFNx and bgfx (Metal) in one app bundle.
#
# x86_64, run by Rosetta 2 on Apple silicon: the lifted code addresses guest memory at the
# game's own 32-bit addresses (RECOMP_FLAT_MEMORY), and only an x86_64 process may map the
# low 4 GB on macOS (arm64 processes must keep a 4 GB __PAGEZERO). See src/mac/.
#
#   cmake -S macos -B build/macos -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
#   cmake --build build/macos
cmake_minimum_required(VERSION 3.20)
set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET 13.0 CACHE STRING "" FORCE)   # SwiftUI NavigationSplitView
set(CMAKE_Swift_COMPILER_TARGET x86_64-apple-macos13.0 CACHE STRING "" FORCE)
project(FF7RecompMac C CXX OBJC OBJCXX ASM Swift)
get_filename_component(FF7_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:-ffile-prefix-map=${FF7_ROOT}=ff7recomp>")

# Every source sees the Linux names the runtime uses (src/mac/include/mac_compat.h).
add_compile_options("$<$<COMPILE_LANGUAGE:C,CXX,OBJC,OBJCXX>:SHELL:-include ${FF7_ROOT}/src/mac/include/mac_compat.h>")
include_directories(AFTER "${FF7_ROOT}/src/mac/include")

set(FF7_WITH_BGFX ON CACHE BOOL "" FORCE)
set(FF7_WITH_FFNX ON CACHE BOOL "" FORCE)
include("${FF7_ROOT}/cmake/ff7core.cmake")

# <ucontext.h> needs _XOPEN_SOURCE on macOS (_DARWIN_C_SOURCE keeps the rest visible).
set_source_files_properties("${FF7_ROOT}/src/host/ff7_crash.c" PROPERTIES COMPILE_DEFINITIONS "_XOPEN_SOURCE=700;_DARWIN_C_SOURCE")

# The launcher (SwiftUI): settings, mods, catalogs (src/mac/launcher), with the Android
# launcher's native mod reader and .7z extractor.
set(FF7_LZMA "${FF7_ROOT}/external/deps/lzma")
set(FF7_LAUNCHER_SOURCES
  "${FF7_ROOT}/src/mac/launcher/Core.swift"
  "${FF7_ROOT}/src/mac/launcher/Mods.swift"
  "${FF7_ROOT}/src/mac/launcher/Saves.swift"
  "${FF7_ROOT}/src/mac/launcher/Achievements.swift"
  "${FF7_ROOT}/src/mac/launcher/Steam.swift"
  "${FF7_ROOT}/src/mac/launcher/GameOverlay.swift"
  "${FF7_ROOT}/src/mac/launcher/Views.swift"
  "${FF7_ROOT}/src/mac/ff7_launcher_native.cpp"
  "${FF7_ROOT}/src/android/un7z.c"
  "${FF7_LZMA}/7zArcIn.c" "${FF7_LZMA}/7zBuf.c" "${FF7_LZMA}/7zCrc.c" "${FF7_LZMA}/7zCrcOpt.c" "${FF7_LZMA}/7zDec.c"
  "${FF7_LZMA}/7zStream.c" "${FF7_LZMA}/7zAlloc.c" "${FF7_LZMA}/7zFile.c" "${FF7_LZMA}/Bcj2.c" "${FF7_LZMA}/Bra.c"
  "${FF7_LZMA}/Bra86.c" "${FF7_LZMA}/BraIA64.c" "${FF7_LZMA}/CpuArch.c" "${FF7_LZMA}/Delta.c" "${FF7_LZMA}/Lzma2Dec.c")
set(FF7_VAR "${FF7_ROOT}/external/7th-Heaven/AppUI/Resources/7thHeaven.var")
set_source_files_properties("${FF7_VAR}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

add_executable(FF7Recomp MACOSX_BUNDLE
  "${FF7_ROOT}/src/mac/ff7_mac_main.mm"
  "${FF7_ROOT}/src/mac/guest_reserve.s"
  ${FF7_LAUNCHER_SOURCES}
  "${FF7_VAR}")
target_include_directories(FF7Recomp PRIVATE "${FF7_ROOT}/src/mods" "${FF7_LZMA}")
target_compile_options(FF7Recomp PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-swift-version;5>")
set_source_files_properties("${FF7_ROOT}/src/mac/ff7_mac_main.mm" PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
target_include_directories(FF7Recomp PRIVATE "${FF7_ROOT}/src/host")
target_link_libraries(FF7Recomp PRIVATE ff7_core ffnx
  "-framework Cocoa" "-framework Metal" "-framework QuartzCore" "-framework GameController" "-framework CoreHaptics"
  "-framework AudioToolbox" "-framework CoreAudio" "-framework IOKit" "-framework SwiftUI" "-framework AppKit")
# Non-PIE at 4 GB, with the guest's [0x10000, 0x80000000) reserved by FF7GUEST.
target_link_options(FF7Recomp PRIVATE
  "LINKER:-no_pie"
  "LINKER:-pagezero_size,0x10000"
  "LINKER:-image_base,0x100000000"
  "LINKER:-segaddr,FF7GUEST,0x10000"
  "LINKER:-segprot,FF7GUEST,rw,rw")
set_target_properties(FF7Recomp PROPERTIES
  OUTPUT_NAME "FF7Recomp"
  MACOSX_BUNDLE_BUNDLE_NAME "FF7Recomp"
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.ff7recomp.mac"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0.2"
  MACOSX_BUNDLE_BUNDLE_VERSION "1")
