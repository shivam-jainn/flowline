#!/usr/bin/env bash
# StepIt architecture & layout gate (docs/PLAN.md, docs/phase1-plan.md §9.2/§11).
#
# Verifies the repository boundaries are intact:
#   1. Core IR layers (Events/, Engine/, Pipeline/) stay Foundation-only.
#   2. The legacy coordinator / typing aggregator stay deleted.
#   3. Capture singletons are not referenced outside Drivers/macOS.
#   4. Removed legacy folders stay removed (StepItCore/Capture/, StepItCore/Playground/).
#   5. Fixture-driven tooling lives in Sources/StepItFixtures and resolves Fixtures/playground-web.
#   6. WebKit stays confined to Publishing/ inside StepItCore.
#   7. No absolute user paths are baked into Sources / Tests / Scripts.
#
# Usage: Scripts/ci/check_architecture.sh   (run from the repo root; exits 1 on any violation)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

check_dir_absent() {
  local title="$1"
  local path="$2"
  if [[ -d "${path}" ]]; then
    echo "❌ ${title} (${path} still exists)"
    failures=$((failures + 1))
  else
    echo "✅ ${title}"
  fi
}

check_dir_present() {
  local title="$1"
  local path="$2"
  if [[ -d "${path}" ]]; then
    echo "✅ ${title}"
  else
    echo "❌ ${title} (${path} is missing)"
    failures=$((failures + 1))
  fi
}

# 1. Core IR layers must stay Foundation-only (no AppKit / Combine / AX / ScreenCaptureKit / WebKit / Vision / CoreImage).
check_empty \
  "Events/, Engine/, Pipeline/ import Foundation only" \
  "^import (AppKit|Combine|ApplicationServices|ScreenCaptureKit|SwiftUI|WebKit|Vision|CoreImage|Carbon)" \
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

# 4. Removed legacy folders must not come back.
check_dir_absent "Sources/StepItCore/Capture/ removed" "Sources/StepItCore/Capture"
check_dir_absent "Sources/StepItCore/Playground/ removed (fixtures live in StepItFixtures)" "Sources/StepItCore/Playground"

# 5. Fixture-driven tooling lives in the StepItFixtures target and resolves Fixtures/playground-web.
check_dir_present "Sources/StepItFixtures/ exists" "Sources/StepItFixtures"
check_empty \
  "No stale Playground/web paths (use Fixtures/playground-web)" \
  "Playground/web" \
  --exclude=check_architecture.sh Sources Tests Scripts

# 6. WebKit stays confined to Publishing/ inside StepItCore (the fixture renderer lives in StepItFixtures).
webkit_leaks="$(grep -RInE "^import WebKit" Sources/StepItCore --include="*.swift" | grep -v "/Publishing/" || true)"
if [[ -n "${webkit_leaks}" ]]; then
  echo "❌ WebKit usage confined to StepItCore/Publishing/"
  echo "${webkit_leaks}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ WebKit usage confined to StepItCore/Publishing/"
fi

# 7. No absolute user paths baked into code, tests, or scripts.
check_empty \
  "No absolute /Users/ paths in Sources/Tests/Scripts" \
  "/Users/" \
  --exclude=check_architecture.sh Sources Tests Scripts

# 8. Phase 0 convention (docs/roadmap.md T0.4): Fixtures/ stays data-only;
#    DataLine tests are PhaseNN*, shared helpers stay in Support/.
if find Fixtures -name "*.swift" -print -quit | grep -q .; then
  echo "❌ Fixtures/ stays data-only (found .swift under Fixtures/)"
  find Fixtures -name "*.swift" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ Fixtures/ stays data-only (no .swift)"
fi

if [[ ! -f "Tests/StepItTests/Support/DataLineFixtures.swift" ]]; then
  echo "❌ Tests/StepItTests/Support/DataLineFixtures.swift is missing (Phase 0 T0.1)"
  failures=$((failures + 1))
else
  echo "✅ Tests/StepItTests/Support/DataLineFixtures.swift exists"
fi

if [[ ! -f "Tests/StepItTests/Support/GoldenAssertions.swift" ]]; then
  echo "❌ Tests/StepItTests/Support/GoldenAssertions.swift is missing (Phase 0 T0.2)"
  failures=$((failures + 1))
else
  echo "✅ Tests/StepItTests/Support/GoldenAssertions.swift exists"
fi

bad_dataline="$(find Tests/StepItTests/DataLine -name "*.swift" -print 2>/dev/null | grep -vE "/Phase[0-9]+[A-Za-z0-9_]*\.swift$" || true)"
if [[ -n "${bad_dataline}" ]]; then
  echo "❌ Tests/StepItTests/DataLine/ files must be PhaseNN*.swift (Phase 0 T0.4)"
  echo "${bad_dataline}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ Tests/StepItTests/DataLine/ naming is PhaseNN*"
fi

if [[ "${failures}" -gt 0 ]]; then
  echo ""
  echo "Architecture check failed with ${failures} violation(s)."
  exit 1
fi

echo ""
echo "Architecture check passed."
