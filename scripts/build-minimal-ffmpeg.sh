#!/usr/bin/env bash
# Native Linux x64 and Windows x64 bundle for discord.lua voice features.
set -euo pipefail

ROOT="${GITHUB_WORKSPACE:-$(pwd)}"
FFMPEG_TAG="${FFMPEG_TAG:-n9.0.1}"
OPUS_TAG="${OPUS_TAG:-v1.5.2}"
LIBSODIUM_TAG="${LIBSODIUM_TAG:-1.0.22-RELEASE}"
cd "$ROOT"

install_dependencies() {
  local packages=(build-essential cmake git libssl-dev nasm pkg-config gcc-mingw-w64-x86-64)
  if (( EUID == 0 )); then
    apt-get update
    apt-get install -y "${packages[@]}"
  else
    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
  fi
}

build_opus() {
  local build_dir="$1" install_dir="$2"
  shift 2
  cmake -S opus-src -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DOPUS_BUILD_PROGRAMS=OFF \
    -DOPUS_BUILD_TESTING=OFF \
    "$@"
  cmake --build "$build_dir" --parallel "$(nproc)"
  cmake --install "$build_dir"
}

copy_artifact() {
  local root="$1" pattern="$2" destination="$3" source
  source="$(find "$root" -type f -iname "$pattern" -print -quit)"
  if [[ -z "$source" ]]; then
    echo "Missing artifact matching $pattern under $root" >&2
    exit 1
  fi
  install -D -m 755 "$source" "$destination"
}

COMMON=(
  --disable-doc --disable-debug --disable-everything --disable-shared --enable-static
  --enable-ffmpeg --enable-ffprobe --enable-avcodec --enable-avformat --enable-avutil --enable-swresample
  --enable-network --enable-protocol=file,pipe,http,https,tcp,tls
  --enable-demuxer=aac,ac3,flac,matroska,mov,mp3,mpegts,ogg,wav
  --enable-muxer=adts,mp3,ogg,opus,pcm_s16le,wav,webm
  --enable-parser=aac,ac3,mpegaudio,opus,vorbis
  --enable-decoder=aac,aac_fixed,ac3,flac,mp3,mp3float,mp3adu,mp3on4,opus,pcm_alaw,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le,pcm_mulaw,pcm_s16be,pcm_s16le,pcm_s24be,pcm_s24le,pcm_s32be,pcm_s32le,pcm_u8,pcm_u16be,pcm_u16le,pcm_u24be,pcm_u24le,pcm_u32be,pcm_u32le,vorbis
  --enable-encoder=libopus,pcm_s16le --enable-libopus
)

install_dependencies
git clone --depth 1 --branch "$OPUS_TAG" https://github.com/xiph/opus.git opus-src
git clone --depth 1 --branch "$FFMPEG_TAG" https://github.com/FFmpeg/FFmpeg.git ffmpeg-src
git clone --depth 1 --branch "$LIBSODIUM_TAG" https://github.com/jedisct1/libsodium.git sodium-src

# Recreate every native artifact, retaining the shipped license files.
rm -rf lib/bundle/linux-x64/bin lib/bundle/linux-x64/lib
rm -rf lib/bundle/windows-x64/bin lib/bundle/windows-x64/dll
mkdir -p lib/bundle/linux-x64/bin lib/bundle/linux-x64/lib
mkdir -p lib/bundle/windows-x64/bin lib/bundle/windows-x64/dll

# Linux: static Opus for FFmpeg, then shared Opus for LuaJIT FFI.
build_opus opus-linux-static-build opus-linux-static-install -DOPUS_BUILD_SHARED_LIBRARY=OFF
pushd ffmpeg-src
PKG_CONFIG_PATH="$ROOT/opus-linux-static-install/lib/pkgconfig" ./configure "${COMMON[@]}" \
  --enable-openssl --pkg-config-flags=--static \
  --extra-cflags="-I$ROOT/opus-linux-static-install/include" \
  --extra-ldflags="-static -L$ROOT/opus-linux-static-install/lib" \
  --extra-libs="-ldl -lm -lpthread"
make -j"$(nproc)"
install -m 755 ffmpeg "$ROOT/lib/bundle/linux-x64/bin/ffmpeg"
install -m 755 ffprobe "$ROOT/lib/bundle/linux-x64/bin/ffprobe"
make distclean
popd

build_opus opus-linux-shared-build opus-linux-shared-install -DOPUS_BUILD_SHARED_LIBRARY=ON
cp -L opus-linux-shared-install/lib/libopus.so "$ROOT/lib/bundle/linux-x64/lib/libopus.so"
chmod 755 "$ROOT/lib/bundle/linux-x64/lib/libopus.so"

# Windows: static Opus for FFmpeg, then DLL Opus for LuaJIT FFI.
WINDOWS_CMAKE=(
  -DCMAKE_SYSTEM_NAME=Windows
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc
  -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres
  -DCMAKE_C_FLAGS=-fno-stack-protector
)
build_opus opus-windows-static-build opus-windows-static-install -DOPUS_BUILD_SHARED_LIBRARY=OFF "${WINDOWS_CMAKE[@]}"
mkdir ffmpeg-windows-build
pushd ffmpeg-windows-build
PKG_CONFIG_LIBDIR="$ROOT/opus-windows-static-install/lib/pkgconfig" ../ffmpeg-src/configure "${COMMON[@]}" \
  --arch=x86_64 --target-os=mingw32 --cross-prefix=x86_64-w64-mingw32- --enable-cross-compile \
  --pkg-config=pkg-config --enable-schannel --pkg-config-flags=--static \
  --extra-cflags="-I$ROOT/opus-windows-static-install/include" \
  --extra-ldflags="-static -L$ROOT/opus-windows-static-install/lib" \
  --extra-libs="-lws2_32 -lwinpthread -lm"
make -j"$(nproc)"
install -m 755 ffmpeg.exe "$ROOT/lib/bundle/windows-x64/bin/ffmpeg.exe"
install -m 755 ffprobe.exe "$ROOT/lib/bundle/windows-x64/bin/ffprobe.exe"
popd

build_opus opus-windows-shared-build opus-windows-shared-install -DOPUS_BUILD_SHARED_LIBRARY=ON "${WINDOWS_CMAKE[@]}"
copy_artifact opus-windows-shared-install 'libopus.dll' "$ROOT/lib/bundle/windows-x64/dll/libopus-0.x64.dll"
libssp_dll="$(x86_64-w64-mingw32-gcc -print-file-name=libssp-0.dll)"
if [[ ! -f "$libssp_dll" ]]; then echo "Missing mingw runtime: libssp-0.dll" >&2; exit 1; fi
install -m 755 "$libssp_dll" "$ROOT/lib/bundle/windows-x64/dll/libssp-0.dll"

# libsodium shared libraries for the LuaJIT FFI backend.
pushd sodium-src
./configure --prefix="$ROOT/sodium-linux-install" --disable-static --enable-shared
make -j"$(nproc)"
make install
cp -L "$ROOT/sodium-linux-install/lib/libsodium.so" "$ROOT/lib/bundle/linux-x64/lib/libsodium.so"
chmod 755 "$ROOT/lib/bundle/linux-x64/lib/libsodium.so"
make distclean
popd

mkdir sodium-windows-build
pushd sodium-windows-build
../sodium-src/configure --host=x86_64-w64-mingw32 --prefix="$ROOT/sodium-windows-install" --disable-static --enable-shared
make -j"$(nproc)"
make install
popd
copy_artifact sodium-windows-install 'libsodium*.dll' "$ROOT/lib/bundle/windows-x64/dll/libsodium-x64.dll"

find lib/bundle/linux-x64 lib/bundle/windows-x64 -maxdepth 2 -type f -printf '%p %s bytes\n' | sort
