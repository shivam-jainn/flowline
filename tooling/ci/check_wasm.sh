#!/usr/bin/env bash
# StepIt WASM parity gate (Phase R, M2-07 item 3).
#
# Builds the web package and runs the headless (Node) suite on the same
# golden corpus as Swift (`swift test`) and Rust (`cargo test`).
# Requires: rustup wasm32-unknown-unknown target, wasm-pack, Node.
#
# Usage: tooling/ci/check_wasm.sh   (run from the repo root; exits 1 on failure)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

export PATH="$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin:$PATH"

echo "== wasm-pack build (web) =="
wasm-pack build core/crates/stepit_ffi --target web --out-dir pkg-web

echo "== wasm-pack test (node) =="
(cd core/crates/stepit_ffi && wasm-pack test --node)

echo ""
echo "WASM parity check passed."
