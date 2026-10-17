#!/usr/bin/env bash
# StepIt Phase R exit gate (M1 + M2 + M3): one runner for all three suites.
#
# Runs, in order:
#   1. Swift: `swift build` + `swift test` (source of truth, incl. FFI + windows proofs)
#   2. Architecture gate: `tooling/ci/check_architecture.sh`
#   3. Rust: `tooling/ci/check_rust.sh` (cargo test --workspace + clippy --deny warnings)
#   4. Windows cross-compile: `cargo check -p stepit_win_capture --target x86_64-pc-windows-msvc`
#   5. WASM: `tooling/ci/check_wasm.sh` (wasm-pack build + wasm-pack test --node)
#
# Usage: Scripts/ci/check_phase_r.sh   (run from the repo root; exits 1 on failure)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:$PATH"

echo "===== 1/5 Swift (+ Rust FFI artifacts first) ====="
tooling/toolchain/build-rust-ffi.sh
swift build
swift test

echo "===== 2/5 Architecture gate ====="
tooling/ci/check_architecture.sh

echo "===== 3/5 Rust ====="
tooling/ci/check_rust.sh

echo "===== 4/5 Windows cross-compile ====="
cargo check --manifest-path core/Cargo.toml -p stepit_win_capture --target x86_64-pc-windows-msvc

echo "===== 5/5 WASM ====="
tooling/ci/check_wasm.sh

echo ""
echo "Phase R gate passed (Swift + arch + Rust + Windows-target + WASM)."
