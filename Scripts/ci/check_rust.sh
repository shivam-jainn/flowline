#!/usr/bin/env bash
# StepIt Rust parity gate (Phase R, M2).
#
# Runs the shared fixture suite across the Rust core:
#   cargo test --workspace + cargo clippy --deny warnings
#
# Usage: Scripts/ci/check_rust.sh   (run from the repo root; exits 1 on failure)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}/Rust"

echo "== cargo test --workspace =="
cargo test --workspace --locked

echo "== cargo clippy --deny warnings =="
cargo clippy --workspace --all-targets -- --deny warnings

echo ""
echo "Rust parity check passed."
