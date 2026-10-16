#!/usr/bin/env bash
# StepIt architecture boundary gate (phase1-plan.md §9.2 / §11).
#
# Verifies the Phase 1 boundaries are intact:
#   1. Events/, Engine/ and Pipeline/ stay Foundation-only.
#   2. The legacy coordinator / typing aggregator are gone everywhere.
#   3. Capture singletons are not referenced outside Drivers/macOS.
#
# Usage: Scripts/check_architecture.sh   (run from the repo root; exits 1 on any violation)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

failures=0

check_empty() {
  local title="$1"
  local pattern="$2"
  shift 2
  local matches
  matches="$(grep -RInE "${pattern}" "$@" || true)"
  if [[ -n "${matches}" ]]; then
    echo "❌ ${title}"
    echo "${matches}" | sed 's/^/   /'
    failures=$((failures + 1))
  else
    echo "✅ ${title}"
  fi
}

# 1. Core layers must stay Foundation-only (no AppKit / Combine / AX / ScreenCaptureKit).
check_empty \
  "Events/, Engine/, Pipeline/ import Foundation only" \
  "#import (AppKit|Combine|ApplicationServices|ScreenCaptureKit|SwiftUI|WebKit)" \
  Sources/StepItCore/Events Sources/StepItCore/Engine Sources/StepItCore/Pipeline

# 2. No legacy coordinator or aggregator anywhere (code or comments).
check_empty \
  "No legacy coordinator/aggregator references" \
  "CaptureCoordinator|TextTypingAggregator" \
  Sources Tests

# 3. Pipeline-capture singletons only behind Drivers/macOS.
check_empty \
  "No capture singletons outside Drivers/macOS" \
  "EventMonitor\\.shared|SmartGestureDetector\\.shared|AccessibilityInspector\\.shared" \
  Sources Tests

# 4. The old Capture/ folder must not come back.
if [[ -d Sources/StepItCore/Capture ]]; then
  echo "❌ Sources/StepItCore/Capture/ still exists"
  failures=$((failures + 1))
else
  echo "✅ Sources/StepItCore/Capture/ removed"
fi

if [[ "${failures}" -gt 0 ]]; then
  echo ""
  echo "Architecture check failed with ${failures} violation(s)."
  exit 1
fi

echo ""
echo "Architecture check passed."
