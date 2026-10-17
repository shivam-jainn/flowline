#!/usr/bin/env bash
# StepIt Rust FFI build (Phase R, M2-07).
#
# Rebuilds everything SwiftPM needs from the Rust core:
#   1. `cargo build -p stepit_ffi --release` (cdylib + rlib)
#   2. `uniffi-bindgen generate` (Swift bindings -> apps/desktop/Generated/StepItFFI/)
#   3. `xcodebuild -create-xcframework` (staticlib -> apps/desktop/Generated/stepit_ffiFFI.xcframework)
#
# The .xcframework is gitignored and rebuilt here (CI runs this first).
# Requires: rustup stable toolchain, uniffi-bindgen (cargo install uniffi --features cli), Xcode CLT.
#
# Usage: tooling/toolchain/build-rust-ffi.sh   (run from the repo root)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:$PATH"

echo "== cargo build -p stepit_ffi --release =="
cargo build --manifest-path core/Cargo.toml -p stepit_ffi --release

echo "== uniffi-bindgen (swift) =="
mkdir -p apps/desktop/Generated/StepItFFI
(cd core && uniffi-bindgen generate \
  --library target/release/libstepit_ffi.dylib \
  --language swift \
  --out-dir ../apps/desktop/Generated/StepItFFI)

echo "== stage headers + xcframework =="
mkdir -p apps/desktop/Generated/FFIHeaders
cp apps/desktop/Generated/StepItFFI/stepit_ffiFFI.h apps/desktop/Generated/FFIHeaders/
cp apps/desktop/Generated/StepItFFI/stepit_ffiFFI.modulemap apps/desktop/Generated/FFIHeaders/module.modulemap
# Keep the Swift target dir to generated Swift only (stray C headers break SPM).
rm -f apps/desktop/Generated/StepItFFI/stepit_ffiFFI.h apps/desktop/Generated/StepItFFI/stepit_ffiFFI.modulemap
rm -rf apps/desktop/Generated/stepit_ffiFFI.xcframework
xcodebuild -create-xcframework \
  -library core/target/release/libstepit_ffi.a \
  -headers apps/desktop/Generated/FFIHeaders/ \
  -output apps/desktop/Generated/stepit_ffiFFI.xcframework

echo ""
echo "FFI artifacts ready: apps/desktop/Generated/StepItFFI/stepit_ffi.swift + apps/desktop/Generated/stepit_ffiFFI.xcframework"
