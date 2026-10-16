#!/usr/bin/env bash
# Builds libfvdenoise.so for the Android app's ABIs into <android-app>/src/main/jniLibs.
#   native/denoise/build-android.sh /path/to/FutureVoice-android/android/app
# Needs rustup targets aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
# and an NDK (ANDROID_NDK_HOME, else the newest under ~/Library/Android/sdk/ndk).
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/.cargo/env"
APP="${1:?usage: build-android.sh <android app module dir>}"
NDK="${ANDROID_NDK_HOME:-$(ls -d "$HOME"/Library/Android/sdk/ndk/* | sort -V | tail -1)}"
BIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"
API=26
build() {  # rust-target  clang-prefix  abi
  local up; up=$(echo "$1" | tr 'a-z-' 'A-Z_')
  export "CARGO_TARGET_${up}_LINKER=$BIN/$2$API-clang"
  export "CC_$(echo "$1" | tr '-' '_')=$BIN/$2$API-clang"
  export "AR_$(echo "$1" | tr '-' '_')=$BIN/llvm-ar"
  cargo build --release --lib --target "$1"
  mkdir -p "$APP/src/main/jniLibs/$3"
  cp "target/$1/release/libfvdenoise.so" "$APP/src/main/jniLibs/$3/"
}
build aarch64-linux-android   aarch64-linux-android     arm64-v8a
build armv7-linux-androideabi armv7a-linux-androideabi  armeabi-v7a
build x86_64-linux-android    x86_64-linux-android      x86_64
du -sh "$APP/src/main/jniLibs"/*
