#!/usr/bin/env bash
# StepIt architecture & layout gate (docs/PLAN.md, docs/phase1-plan.md §9.2/§11).
#
# Verifies the repository boundaries are intact (Phase R: modular core):
#   1. Portable modules (IR/Pipeline/Engine/Storage/CaptureAPI) stay
#      Foundation-only (only StepIt* cross-imports allowed).
#   2. The legacy coordinator / typing aggregator stay deleted.
#   3. Named singletons are not referenced outside the composition root + tests.
#   4. Removed legacy folders stay removed (StepItCore/*, Capture/, Playground/).
#   5. Fixture-driven tooling lives in Sources/StepItFixtures and resolves Fixtures/playground-web.
#   6. WebKit/PDFKit stay confined to StepItPublishing (PDFGenerator only);
#      AppKit lives only in StepItMacCapture; AIGateway/Publishing may add
#      CoreGraphics/ImageIO; Permissions impl may add ApplicationServices.
#   7. No absolute user paths are baked into Sources / Tests / Scripts.
#   8. Phase 0 conventions (Fixtures/ data-only, DataLine PhaseNN*/PhaseRNN*).
#   9. MiniApps never import core modules.
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

# 1. Portable modules must stay Foundation-only (no platform frameworks;
#    only StepIt* cross-imports allowed).
check_empty \
  "StepIt{IR,Pipeline,Engine,Storage,CaptureAPI} import Foundation only" \
  "^import (AppKit|Combine|ApplicationServices|ScreenCaptureKit|SwiftUI|WebKit|Vision|CoreImage|Carbon|AVFoundation|CoreGraphics|ImageIO|UniformTypeIdentifiers|PDFKit)" \
  Sources/StepItIR Sources/StepItPipeline Sources/StepItEngine Sources/StepItStorage Sources/StepItCaptureAPI

# 1b. AIGateway/Publishing may add CoreGraphics/ImageIO only (no AppKit/AX/UI).
check_empty \
  "StepIt{AIGateway,Publishing} import Foundation (+CoreGraphics/ImageIO) only" \
  "^import (AppKit|Combine|ApplicationServices|ScreenCaptureKit|SwiftUI|Vision|CoreImage|Carbon|AVFoundation)" \
  Sources/StepItAIGateway Sources/StepItPublishing

# 1c. Permissions protocol file stays Foundation-only; the macOS impl may use
#     ApplicationServices/CoreGraphics for status checks and prompts.
check_empty \
  "StepItPermissions free of AppKit/SwiftUI/Combine" \
  "^import (AppKit|SwiftUI|Combine)" \
  Sources/StepItPermissions

# 2. No legacy coordinator or aggregator anywhere (code or comments).
check_empty \
  "No legacy coordinator/aggregator references" \
  "CaptureCoordinator|TextTypingAggregator" \
  Sources Tests

# 3. Named singletons resolve only at the composition root (or in tests, which
#    are exempt). Defining modules keep their `shared` shims; call sites must
#    not name them.
check_empty \
  "No named singletons outside composition root" \
  "(SessionStore|ScreenRecorder|MicroClipRecorder|PublishingCoordinator|AIGatewayClient|EventMonitor|SmartGestureDetector|AccessibilityInspector)\.shared" \
  Sources/StepIt/UI Sources/StepIt/CLI Sources/StepIt/main.swift Sources/StepItFixtures Sources/StepItIR Sources/StepItPipeline Sources/StepItEngine Sources/StepItStorage Sources/StepItCaptureAPI Sources/StepItMacCapture Sources/StepItPublishing Sources/StepItAIGateway Sources/StepItPermissions

# 4. Removed legacy folders must not come back.
check_dir_absent "Sources/StepItCore/ removed (R/M1-08 husk deletion)" "Sources/StepItCore"
check_dir_absent "Sources/StepItCore/Capture/ removed" "Sources/StepItCore/Capture"
check_dir_absent "Sources/StepItCore/Playground/ removed (fixtures live in StepItFixtures)" "Sources/StepItCore/Playground"

# 5. Fixture-driven tooling lives in the StepItFixtures target and resolves Fixtures/playground-web.
check_dir_present "Sources/StepItFixtures/ exists" "Sources/StepItFixtures"
check_empty \
  "No stale Playground/web paths (use Fixtures/playground-web)" \
  "Playground/web" \
  --exclude=check_architecture.sh Sources Tests Scripts

# 6. WebKit/PDFKit stay confined to StepItPublishing/PDFGenerator.swift;
#    AppKit stays confined to StepItMacCapture (the fixture renderer lives in
#    StepItFixtures and uses WebKit only through its own target).
webkit_leaks="$(grep -RInE "^import WebKit" Sources --include="*.swift" | grep -v "Sources/StepItPublishing/PDFGenerator.swift" | grep -v "Sources/StepItFixtures/" || true)"
if [[ -n "${webkit_leaks}" ]]; then
  echo "❌ WebKit usage confined to StepItPublishing/PDFGenerator.swift (+ fixtures)"
  echo "${webkit_leaks}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ WebKit usage confined to StepItPublishing/PDFGenerator.swift (+ fixtures)"
fi
pdfkit_leaks="$(grep -RInE "^import PDFKit" Sources --include="*.swift" | grep -v "Sources/StepItPublishing/PDFGenerator.swift" || true)"
if [[ -n "${pdfkit_leaks}" ]]; then
  echo "❌ PDFKit usage confined to StepItPublishing/PDFGenerator.swift"
  echo "${pdfkit_leaks}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ PDFKit usage confined to StepItPublishing/PDFGenerator.swift"
fi
appkit_leaks="$(grep -RInE "^import AppKit" Sources/StepItIR Sources/StepItPipeline Sources/StepItEngine Sources/StepItStorage Sources/StepItCaptureAPI Sources/StepItPublishing Sources/StepItAIGateway Sources/StepItPermissions --include="*.swift" || true)"
if [[ -n "${appkit_leaks}" ]]; then
  echo "❌ AppKit usage confined to StepItMacCapture + surfaces/fixtures"
  echo "${appkit_leaks}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ AppKit usage confined to StepItMacCapture + surfaces/fixtures"
fi

# 7. No absolute user paths baked into code, tests, or scripts.
check_empty \
  "No absolute /Users/ paths in Sources/Tests/Scripts" \
  "/Users/" \
  --exclude=check_architecture.sh Sources Tests Scripts

# 8. Phase 0 convention (docs/roadmap/ T0.4): Fixtures/ stays data-only;
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

bad_dataline="$(find Tests/StepItTests/DataLine -name "*.swift" -print 2>/dev/null | grep -vE "/Phase(R[0-9]+[A-Za-z0-9_]*|[0-9]+[A-Za-z0-9_]*)\.swift$" || true)"
if [[ -n "${bad_dataline}" ]]; then
  echo "❌ Tests/StepItTests/DataLine/ files must be PhaseNN*.swift (Phase 0 T0.4)"
  echo "${bad_dataline}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ Tests/StepItTests/DataLine/ naming is PhaseNN*"
fi

# 9. MiniApps never import core modules (R/M1-08: reviewer surfaces stay decoupled).
check_empty \
  "MiniApps import no StepIt modules" \
  "^import StepIt" \
  Sources/StepIt/UI/MiniApps

if [[ "${failures}" -gt 0 ]]; then
  echo ""
  echo "Architecture check failed with ${failures} violation(s)."
  exit 1
fi

echo ""
echo "Architecture check passed."
