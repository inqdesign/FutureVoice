#!/usr/bin/env bash
# Builds FVDenoise.xcframework (device + simulator) into FutureVoice/Vendor/.
# Needs rustup with aarch64-apple-ios, aarch64-apple-ios-sim and x86_64-apple-ios.
#   native/denoise/build-ios.sh
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/.cargo/env"
export IPHONEOS_DEPLOYMENT_TARGET=17.0
cargo build --release --lib --target aarch64-apple-ios
cargo build --release --lib --target aarch64-apple-ios-sim
cargo build --release --lib --target x86_64-apple-ios
mkdir -p target/ios-sim-universal
lipo -create target/aarch64-apple-ios-sim/release/libfvdenoise.a target/x86_64-apple-ios/release/libfvdenoise.a \
  -output target/ios-sim-universal/libfvdenoise.a
HDR=target/xcframework-headers
rm -rf "$HDR" && mkdir -p "$HDR"
cp include.h "$HDR/fvdenoise.h"
cat > "$HDR/module.modulemap" <<'MAP'
module FVDenoise {
    header "fvdenoise.h"
    link "fvdenoise"
    export *
}
MAP
OUT=../../FutureVoice/Vendor/FVDenoise.xcframework
rm -rf "$OUT"
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libfvdenoise.a -headers "$HDR" \
  -library target/ios-sim-universal/libfvdenoise.a -headers "$HDR" \
  -output "$OUT"
du -sh "$OUT"
