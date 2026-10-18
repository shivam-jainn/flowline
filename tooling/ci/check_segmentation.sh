#!/usr/bin/env bash
# Flowline segmentation gate: post-hoc repair (false cuts / false joins).
#
# Runs the eval harness across the seven golden cases in
# shared/goldens/segmentation.*.json:
#   1. parity_harness metric unit tests (false_cut_rate, false_join_rate,
#      WindowDiff, Pk, segmentation F1) — prints sample reports.
#   2. Pipeline repair eval (coalesce then split) — prints the per-case
#      before → after metric table and asserts the golden outcome + baselines.
#   3. Engine session-wrapper eval — same checks through repair_session.
#
# The +2pp gate lives in the tests themselves
# (parity_harness::segmentation::check_gate): any metric regressing more than
# 0.02 absolute vs the golden baselines fails the test and this script.
#
# Usage: tooling/ci/check_segmentation.sh   (run from the repo root; exits 1 on failure)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}/core"

echo "== segmentation metrics (parity_harness) =="
cargo test -p parity_harness --test segmentation_metrics -- --nocapture

echo "== post-hoc repair eval (flowline_pipeline: coalesce + split) =="
cargo test -p flowline_pipeline --test repair_eval -- --nocapture

echo "== post-hoc repair eval (flowline_engine session wrapper) =="
cargo test -p flowline_engine --test postpass_eval -- --nocapture

echo ""
echo "Segmentation gate passed (no +2pp regression vs shared/goldens/segmentation.*.json)."
