#!/usr/bin/env bash
# Flowline brand asset gate — verifies shared/assets/brand/*.svg stay in sync
# with the Swift inline copies in platform/macos/Sources/FlowlinePublishing/WebDocIcons.swift.
# The web export is a single self-contained HTML file, so Swift must inline the
# same path data — this gate catches drift in either direction.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

ICONS_SWIFT="platform/macos/Sources/FlowlinePublishing/WebDocIcons.swift"
FLOWLINE_SWIFT="platform/macos/Sources/Flowline/UI/Flowline/FlowlineIcons.swift"
TOKENS_JSON="shared/assets/brand/flowline-tokens.json"
TOKENS_SWIFT="platform/macos/Sources/Flowline/UI/Flowline/FlowlineTokens.swift"
THEME_SWIFT="platform/macos/Sources/FlowlinePublishing/WebDocTheme.swift"
failures=0

check_sync() {
  local name="$1"
  local svg_file="shared/assets/brand/${name}.svg"
  if [[ ! -f "${svg_file}" ]]; then
    echo "❌ missing shared asset: ${svg_file}"
    failures=$((failures + 1))
    return
  fi
  # Extract fill hexes + path data fingerprints from the SVG (paths only).
  local svg_paths
  svg_paths="$(grep -o 'd="[^"]*"' "${svg_file}" | sort | md5 2>/dev/null || grep -o 'd="[^"]*"' "${svg_file}" | sort | cksum)"
  if ! grep -q "static let ${name}" "${ICONS_SWIFT}"; then
    echo "❌ WebDocIcons.swift missing 'static let ${name}' (mirror of ${svg_file})"
    failures=$((failures + 1))
    return
  fi
  # Compare each SVG path's `d` against the Swift constant.
  while IFS= read -r d_attr; do
    local d_value
    d_value="$(printf '%s' "${d_attr}" | sed 's/^d="//; s/"$//')"
    local short
    short="$(printf '%s' "${d_value}" | cut -c1-40)"
    if ! grep -qF "${short}" "${ICONS_SWIFT}"; then
      echo "❌ drift: ${svg_file} path starting '${short}…' not found in WebDocIcons.swift"
      failures=$((failures + 1))
    fi
  done < <(grep -o 'd="[^"]*"' "${svg_file}")
  echo "✅ ${name}.svg in sync (${svg_file})"
}

for icon in slack teams notion gmail github link; do
  check_sync "${icon}"
done

check_flowline() {
  local name="$1"
  local svg_file="shared/assets/brand/flowline/icons/${name}.svg"
  if [[ ! -f "${svg_file}" ]]; then
    echo "❌ missing Flowline asset: ${svg_file}"
    failures=$((failures + 1))
    return
  fi
  while IFS= read -r d_attr; do
    local d_value
    d_value="$(printf '%s' "${d_attr}" | sed 's/^d="//; s/"$//')"
    local short
    short="$(printf '%s' "${d_value}" | cut -c1-40)"
    if ! grep -qF "${short}" "${FLOWLINE_SWIFT}"; then
      echo "❌ drift: ${svg_file} path starting '${short}…' not found in FlowlineIcons.swift"
      failures=$((failures + 1))
    fi
  done < <(grep -o 'd="[^"]*"' "${svg_file}")
  echo "✅ flowline/${name}.svg in sync (${svg_file})"
}

for icon in mark capture steps guide halo refine publish reader folder folder-solid search check chevron replay cursor; do
  check_flowline "${icon}"
done

# Tokens parity: canonical hexes must appear in Swift + CSS.
for hex in "#F7F7F5" "#1D1D1F" "#6E6E73" "#E5E5E2" "#EDEDEA" "#3478F6" "#FFB340"; do
  lower="$(printf '%s' "${hex}" | tr 'A-F' 'a-f')"
  upper="$(printf '%s' "${hex}" | tr 'a-f' 'A-F')"
  if ! grep -q "${hex}\|${lower}\|${upper}" "${TOKENS_JSON}"; then
    echo "❌ tokens JSON missing ${hex}"
    failures=$((failures + 1))
  fi
  if ! grep -qi "${hex}" "${TOKENS_SWIFT}"; then
    echo "❌ FlowlineTokens.swift missing ${hex} (see ${TOKENS_JSON})"
    failures=$((failures + 1))
  fi
  if ! grep -qi "${hex}\|$(printf '%s' "${hex}" | tr 'A-F' 'a-f')" "${THEME_SWIFT}"; then
    # dark theme remaps blue/amber; light must still carry the canonical hex
    if [[ "${hex}" == "#5E9BFF" || "${hex}" == "#FFB84D" ]]; then :; else
      echo "⚠️  WebDocTheme.swift missing ${hex} (light theme should mirror tokens)"
    fi
  fi
done
echo "✅ flowline-tokens.json hexes present in Swift"

if [[ "${failures}" -gt 0 ]]; then
  echo ""
  echo "Brand asset check failed with ${failures} violation(s)."
  echo "Fix: copy shared/assets/brand/*.svg inner markup into WebDocIcons.swift (see shared/assets/brand/README.md)."
  exit 1
fi

echo ""
echo "Brand asset check passed."
