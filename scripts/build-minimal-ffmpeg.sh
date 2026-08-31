#!/usr/bin/env bash
# Minimal static FFmpeg bundle for discord.lua voice audio sources.
set -euo pipefail
ROOT="${GITHUB_WORKSPACE:-$(pwd)}"; FFMPEG_TAG="${FFMPEG_TAG:-n9.0.1}"; OPUS_TAG="${OPUS_TAG:-v1.5.2}"
cd "$ROOT"
sudo apt-get update
sudo apt-get install -y build-essential cmake git libssl-dev nasm pkg-config gcc-mingw-w64-x86-64
git clone --depth 1 --branch "$OPUS_TAG" https://github.com/xiph/opus.git opus-src
git clone --depth 1 --branch "$FFMPEG_TAG" https://github.com/FFmpeg/FFmpeg.git ffmpeg-src

build_opus() {
  local build_dir="$1" install_dir="$2"
  shift 2
  cmake -S opus-src -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$install_dir" -DOPUS_BUILD_SHARED_LIBRARY=OFF -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF "$@"
  cmake --build "$build_dir" --parallel "$(nproc)"; cmake --install "$build_dir"
}
COMMON=(--disable-doc --disable-debug --disable-everything --disable-shared --enable-static --enable-ffmpeg --enable-ffprobe --enable-avcodec --enable-avformat --enable-avutil --enable-swresample --enable-network --enable-protocol=file,pipe,http,https,tcp,tls --enable-demuxer=aac,ac3,flac,matroska,mov,mp3,mpegts,ogg,wav --enable-muxer=adts,mp3,ogg,opus,pcm_s16le,wav,webm --enable-parser=aac,ac3,mpegaudio,opus,vorbis --enable-decoder=aac,aac_fixed,ac3,flac,mp3,mp3float,mp3adu,mp3on4,opus,pcm_alaw,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le,pcm_mulaw,pcm_s16be,pcm_s16le,pcm_s24be,pcm_s24le,pcm_s32be,pcm_s32le,pcm_u8,pcm_u16be,pcm_u16le,pcm_u24be,pcm_u24le,pcm_u32be,pcm_u32le,vorbis --enable-encoder=libopus,pcm_s16le --enable-libopus)

# Keep DAVE, Opus and libsodium; remove only old FFmpeg dynamic artifacts.
rm -f lib/bundle/linux-x64/bin/ffmpeg* lib/bundle/linux-x64/bin/ffprobe* lib/bundle/linux-x64/lib/libav*.so* lib/bundle/linux-x64/lib/libsw*.so* lib/bundle/windows-x64/bin/ffmpeg.exe lib/bundle/windows-x64/bin/ffprobe.exe lib/bundle/windows-x64/dll/avcodec-*.dll lib/bundle/windows-x64/dll/avdevice-*.dll lib/bundle/windows-x64/dll/avfilter-*.dll lib/bundle/windows-x64/dll/avformat-*.dll lib/bundle/windows-x64/dll/avutil-*.dll lib/bundle/windows-x64/dll/swresample-*.dll lib/bundle/windows-x64/dll/swscale-*.dll
mkdir -p lib/bundle/linux-x64/bin lib/bundle/windows-x64/bin

build_opus opus-linux-build opus-linux-install ""
pushd ffmpeg-src
PKG_CONFIG_PATH="$ROOT/opus-linux-install/lib/pkgconfig" ./configure ${COMMON[@]} --enable-openssl --pkg-config-flags=--static --extra-cflags="-I$ROOT/opus-linux-install/include" --extra-ldflags="-static -L$ROOT/opus-linux-install/lib" --extra-libs="-ldl -lm -lpthread"
make -j"$(nproc)"; cp ffmpeg "$ROOT/lib/bundle/linux-x64/bin/"; cp ffprobe "$ROOT/lib/bundle/linux-x64/bin/"; popd

# The Linux build configures the source tree in place. Remove its generated
# configuration before configuring the Windows build out of tree.
pushd ffmpeg-src
make distclean
popd

build_opus opus-windows-build opus-windows-install \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres
mkdir ffmpeg-windows-build; pushd ffmpeg-windows-build
PKG_CONFIG_LIBDIR="$ROOT/opus-windows-install/lib/pkgconfig" ../ffmpeg-src/configure ${COMMON[@]} --arch=x86_64 --target-os=mingw32 --cross-prefix=x86_64-w64-mingw32- --enable-cross-compile --pkg-config=pkg-config --enable-schannel --pkg-config-flags=--static --extra-cflags="-I$ROOT/opus-windows-install/include" --extra-ldflags="-static -L$ROOT/opus-windows-install/lib" --extra-libs="-lws2_32 -lwinpthread -lm"
make -j"$(nproc)"; cp ffmpeg.exe "$ROOT/lib/bundle/windows-x64/bin/"; cp ffprobe.exe "$ROOT/lib/bundle/windows-x64/bin/"; popd
command -v file >/dev/null && file lib/bundle/linux-x64/bin/ffmpeg lib/bundle/windows-x64/bin/ffmpeg.exe
du -h lib/bundle/linux-x64/bin/ffmpeg lib/bundle/windows-x64/bin/ffmpeg.exe
