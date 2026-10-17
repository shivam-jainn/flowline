#!/usr/bin/env bash
# StepIt architecture & layout gate (docs/PLAN.md, docs/phase1-plan.md §9.2/§11).
#
# Monolith map (turborepo-style):
#   apps/desktop     SwiftPM package — ALL Swift lives here
#   core/            Cargo workspace — ALL Rust lives here
#   shared/          Language-agnostic: contracts, fixtures, goldens (data only)
#   platform/        Per-OS signposts (macos → apps/desktop, windows → core/…)
#   tooling/         Builds + gates (this file lives in tooling/ci/)
#
# Verifies the repository boundaries are intact (Phase R: modular core):
#   1. Portable modules (IR/Pipeline/Engine/Storage/CaptureAPI) stay
#      Foundation-only (only StepIt* cross-imports allowed).
#   2. The legacy coordinator / typing aggregator stay deleted.
#   3. Named singletons are not referenced outside the composition root + tests.
#   4. Removed legacy folders stay removed (StepItCore/*, Capture/, Playground/).
#   5. Fixture-driven tooling lives in apps/desktop Sources/StepItFixtures and
#      resolves shared/fixtures/playground-web.
#   6. WebKit/PDFKit stay confined to StepItPublishing (PDFGenerator only);
#      AppKit lives only in StepItMacCapture; AIGateway/Publishing may add
#      CoreGraphics/ImageIO; Permissions impl may add ApplicationServices.
#   7. No absolute user paths are baked into code, tests, or scripts.
#   8. Phase 0 conventions (shared/fixtures/ data-only, DataLine PhaseNN*/PhaseRNN*).
#   9. MiniApps never import core modules.
#   10. Language separation: no Swift under core/, no Rust under apps/,
#      no code at all under shared/ (contracts/fixtures/goldens are data).
#
# Usage: tooling/ci/check_architecture.sh   (run from the repo root; exits 1 on any violation)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

SWIFT_SOURCES="apps/desktop/Sources"
SWIFT_TESTS="apps/desktop/Tests"

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
  "${SWIFT_SOURCES}/StepItIR" "${SWIFT_SOURCES}/StepItPipeline" "${SWIFT_SOURCES}/StepItEngine" "${SWIFT_SOURCES}/StepItStorage" "${SWIFT_SOURCES}/StepItCaptureAPI"

# 1b. AIGateway/Publishing may add CoreGraphics/ImageIO only (no AppKit/AX/UI).
check_empty \
  "StepIt{AIGateway,Publishing} import Foundation (+CoreGraphics/ImageIO) only" \
  "^import (AppKit|Combine|ApplicationServices|ScreenCaptureKit|SwiftUI|Vision|CoreImage|Carbon|AVFoundation)" \
  "${SWIFT_SOURCES}/StepItAIGateway" "${SWIFT_SOURCES}/StepItPublishing"

# 1c. Permissions protocol file stays Foundation-only; the macOS impl may use
#     ApplicationServices/CoreGraphics for status checks and prompts.
check_empty \
  "StepItPermissions free of AppKit/SwiftUI/Combine" \
  "^import (AppKit|SwiftUI|Combine)" \
  "${SWIFT_SOURCES}/StepItPermissions"

# 2. No legacy coordinator or aggregator anywhere (code or comments).
check_empty \
  "No legacy coordinator/aggregator references" \
  "CaptureCoordinator|TextTypingAggregator" \
  "${SWIFT_SOURCES}" "${SWIFT_TESTS}"

# 3. Named singletons resolve only at the composition root (or in tests, which
#    are exempt). Defining modules keep their `shared` shims; call sites must
#    not name them.
check_empty \
  "No named singletons outside composition root" \
  "(SessionStore|ScreenRecorder|MicroClipRecorder|PublishingCoordinator|AIGatewayClient|EventMonitor|SmartGestureDetector|AccessibilityInspector)\.shared" \
  "${SWIFT_SOURCES}/StepIt/UI" "${SWIFT_SOURCES}/StepIt/CLI" "${SWIFT_SOURCES}/StepIt/main.swift" "${SWIFT_SOURCES}/StepItFixtures" "${SWIFT_SOURCES}/StepItIR" "${SWIFT_SOURCES}/StepItPipeline" "${SWIFT_SOURCES}/StepItEngine" "${SWIFT_SOURCES}/StepItStorage" "${SWIFT_SOURCES}/StepItCaptureAPI" "${SWIFT_SOURCES}/StepItMacCapture" "${SWIFT_SOURCES}/StepItPublishing" "${SWIFT_SOURCES}/StepItAIGateway" "${SWIFT_SOURCES}/StepItPermissions"

# 4. Removed legacy folders must not come back.
check_dir_absent "apps/desktop/Sources/StepItCore/ removed (R/M1-08 husk deletion)" "apps/desktop/Sources/StepItCore"
check_dir_absent "apps/desktop/Sources/StepItCore/Capture/ removed" "apps/desktop/Sources/StepItCore/Capture"
check_dir_absent "apps/desktop/Sources/StepItCore/Playground/ removed (fixtures live in StepItFixtures)" "apps/desktop/Sources/StepItCore/Playground"
check_dir_absent "Repo-root Sources/ removed (Swift lives in apps/desktop/)" "Sources"
check_dir_absent "Repo-root Tests/ removed (Swift lives in apps/desktop/)" "Tests"
check_dir_absent "Repo-root Rust/ removed (Rust lives in core/)" "Rust"
check_dir_absent "Repo-root Scripts/ removed (scripts live in tooling/)" "Scripts"
check_dir_absent "Repo-root Fixtures/ removed (fixtures live in shared/fixtures/)" "Fixtures"

# 5. Fixture-driven tooling lives in the StepItFixtures target and resolves shared/fixtures/playground-web.
check_dir_present "apps/desktop/Sources/StepItFixtures/ exists" "${SWIFT_SOURCES}/StepItFixtures"
check_empty \
  "No stale Playground/web paths (use shared/fixtures/playground-web)" \
  "Playground/web" \
  --exclude=check_architecture.sh "${SWIFT_SOURCES}" "${SWIFT_TESTS}" tooling
# The app-bundle copy keeps the historical `Fixtures/` leaf inside
# Resources/ (FixtureLocator step 4); allowlist that single destination.
if grep -RInE '"Fixtures/|/Fixtures/|\(Fixtures/' "${SWIFT_SOURCES}" "${SWIFT_TESTS}" tooling --exclude=check_architecture.sh 2>/dev/null | grep -v 'RESOURCES_DIR}/Fixtures/' | grep -q .; then
  echo "❌ No stale Fixtures/ root paths (use shared/fixtures/)"
  grep -RInE '"Fixtures/|/Fixtures/|\(Fixtures/' "${SWIFT_SOURCES}" "${SWIFT_TESTS}" tooling --exclude=check_architecture.sh | grep -v 'RESOURCES_DIR}/Fixtures/' | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ No stale Fixtures/ root paths (use shared/fixtures/)"
fi

# 6. WebKit/PDFKit stay confined to StepItPublishing/PDFGenerator.swift;
#    AppKit stays confined to StepItMacCapture (the fixture renderer lives in
#    StepItFixtures and uses WebKit only through its own target).
webkit_leaks="$(grep -RInE "^import WebKit" "${SWIFT_SOURCES}" --include="*.swift" | grep -v "${SWIFT_SOURCES}/StepItPublishing/PDFGenerator.swift" | grep -v "${SWIFT_SOURCES}/StepItFixtures/" || true)"
if [[ -n "${webkit_leaks}" ]]; then
  echo "❌ WebKit usage confined to StepItPublishing/PDFGenerator.swift (+ fixtures)"
  echo "${webkit_leaks}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ WebKit usage confined to StepItPublishing/PDFGenerator.swift (+ fixtures)"
fi
pdfkit_leaks="$(grep -RInE "^import PDFKit" "${SWIFT_SOURCES}" --include="*.swift" | grep -v "${SWIFT_SOURCES}/StepItPublishing/PDFGenerator.swift" || true)"
if [[ -n "${pdfkit_leaks}" ]]; then
  echo "❌ PDFKit usage confined to StepItPublishing/PDFGenerator.swift"
  echo "${pdfkit_leaks}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ PDFKit usage confined to StepItPublishing/PDFGenerator.swift"
fi
appkit_leaks="$(grep -RInE "^import AppKit" "${SWIFT_SOURCES}/StepItIR" "${SWIFT_SOURCES}/StepItPipeline" "${SWIFT_SOURCES}/StepItEngine" "${SWIFT_SOURCES}/StepItStorage" "${SWIFT_SOURCES}/StepItCaptureAPI" "${SWIFT_SOURCES}/StepItPublishing" "${SWIFT_SOURCES}/StepItAIGateway" "${SWIFT_SOURCES}/StepItPermissions" --include="*.swift" || true)"
if [[ -n "${appkit_leaks}" ]]; then
  echo "❌ AppKit usage confined to StepItMacCapture + surfaces/fixtures"
  echo "${appkit_leaks}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ AppKit usage confined to StepItMacCapture + surfaces/fixtures"
fi

# 7. No absolute user paths baked into code, tests, or scripts.
check_empty \
  "No absolute home-directory paths in code/tests/tooling" \
  "/Users/" \
  --exclude=check_architecture.sh "${SWIFT_SOURCES}" "${SWIFT_TESTS}" tooling

# 8. Phase 0 convention (docs/roadmap/ T0.4): shared/fixtures/ stays data-only;
#    DataLine tests are PhaseNN*, shared helpers stay in Support/.
if find shared/fixtures shared/goldens shared/contracts -name "*.swift" -print -quit 2>/dev/null | grep -q .; then
  echo "❌ shared/ stays data-only (found .swift under shared/)"
  find shared/fixtures shared/goldens shared/contracts -name "*.swift" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ shared/ stays data-only (no .swift)"
fi

if [[ ! -f "${SWIFT_TESTS}/StepItTests/Support/DataLineFixtures.swift" ]]; then
  echo "❌ apps/desktop/Tests/StepItTests/Support/DataLineFixtures.swift is missing (Phase 0 T0.1)"
  failures=$((failures + 1))
else
  echo "✅ apps/desktop/Tests/StepItTests/Support/DataLineFixtures.swift exists"
fi

if [[ ! -f "${SWIFT_TESTS}/StepItTests/Support/GoldenAssertions.swift" ]]; then
  echo "❌ apps/desktop/Tests/StepItTests/Support/GoldenAssertions.swift is missing (Phase 0 T0.2)"
  failures=$((failures + 1))
else
  echo "✅ apps/desktop/Tests/StepItTests/Support/GoldenAssertions.swift exists"
fi

bad_dataline="$(find "${SWIFT_TESTS}/StepItTests/DataLine" -name "*.swift" -print 2>/dev/null | grep -vE "/Phase(R[0-9]+[A-Za-z0-9_]*|[0-9]+[A-Za-z0-9_]*)\.swift$" || true)"
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
  "${SWIFT_SOURCES}/StepIt/UI/MiniApps"

# 10. Language separation: Swift lives in apps/desktop, Rust in core,
#     shared/ is data (contracts/fixtures/goldens) — no code anywhere else.
swift_in_core="$(find core -name "*.swift" -not -path "*/target/*" -print 2>/dev/null || true)"
if [[ -n "${swift_in_core}" ]]; then
  echo "❌ No Swift under core/ (Rust workspace is Swift-free)"
  echo "${swift_in_core}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ No Swift under core/"
fi
rust_in_apps="$(find apps -name "*.rs" -print 2>/dev/null || true)"
if [[ -n "${rust_in_apps}" ]]; then
  echo "❌ No Rust under apps/ (Swift package is Rust-free)"
  echo "${rust_in_apps}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ No Rust under apps/"
fi
code_in_shared="$(find shared -name "*.swift" -o -name "*.rs" -print 2>/dev/null || true)"
if [[ -n "${code_in_shared}" ]]; then
  echo "❌ shared/ is data-only (no .swift/.rs under shared/)"
  echo "${code_in_shared}" | sed 's/^/   /'
  failures=$((failures + 1))
else
  echo "✅ shared/ is data-only (contracts/fixtures/goldens)"
fi

if [[ "${failures}" -gt 0 ]]; then
  echo ""
  echo "Architecture check failed with ${failures} violation(s)."
  exit 1
fi

echo ""
echo "Architecture check passed."
