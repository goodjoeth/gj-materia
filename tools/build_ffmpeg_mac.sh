#!/usr/bin/env bash
# FFmpeg n9.0.2 (FFNx's pin) for macOS x86_64 (tools/build_ffmpeg_android.sh for the Mac):
# FF7's movies are Matroska with VP8 video and Vorbis audio.
# Output: build/ffmpeg-mac/{include,lib}
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/external/deps/ffmpeg"
OUT="$ROOT/build/ffmpeg-mac"
[ -d "$SRC" ] || git -c advice.detachedHead=false clone -q --depth 1 -b n9.0.2 https://github.com/FFmpeg/FFmpeg.git "$SRC"
mkdir -p "$OUT/build"
cd "$OUT/build"
"$SRC/configure" \
  --prefix="$OUT" \
  --arch=x86_64 --enable-cross-compile --target-os=darwin \
  --cc="clang -arch x86_64 -mmacosx-version-min=12.0" --cxx="clang++ -arch x86_64 -mmacosx-version-min=12.0" \
  --pkg-config=false \
  --enable-static --disable-shared --enable-pic \
  --disable-programs --disable-doc --disable-debug --disable-avdevice --disable-avfilter \
  --disable-everything --disable-x86asm \
  --disable-videotoolbox --disable-audiotoolbox --disable-securetransport --disable-iconv --disable-lzma --disable-bzlib \
  --enable-avcodec --enable-avformat --enable-avutil --enable-swscale --enable-swresample \
  --enable-protocol=file \
  --enable-demuxer=matroska,ogg,avi,mov,mp3,wav \
  --enable-decoder=vp8,vp9,vorbis,opus,h264,mpeg4,aac,mp3,pcm_s16le,adpcm_ms \
  --enable-parser=vp8,vp9,vorbis,opus,h264,mpeg4video,aac,mpegaudio \
  --extra-cflags="-O2 -fPIC" > "$OUT/configure.log" 2>&1 || { tail -30 "$OUT/configure.log"; exit 1; }
make -j"$(sysctl -n hw.ncpu)" > "$OUT/make.log" 2>&1 || { tail -30 "$OUT/make.log"; exit 1; }
make install > "$OUT/install.log" 2>&1
ls -la "$OUT/lib"
