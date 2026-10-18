# shared/assets/brand/ — canonical brand marks (cross-platform)

## Share-menu marks (third-party)

**Single source of truth** for every brand glyph in the Share dropdown.
`platform/macos` (and later `platform/windows`, web exports) inline these
files verbatim — never paste ad-hoc SVGs elsewhere.

| File | Brand | Tile | Rule |
|---|---|---|---|
| `slack.svg` | Slack octothorpe, full color | white 28px tile, 16px mark | Full-color on white/black/aubergine `#4A154B` only. Source: <https://slack.com/media-kit>. Never recolor, reshuffle, or imply endorsement. |
| `teams.svg` | **Fallback** Teams glyph, official flats `#464EB8` / `#7B83EB` | `#464EB8` tile, white knockout | Official 2025 gradient vector is trademark-gated (needs express license per <https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks>). This MIT-derived fallback ships until approval — swap 1:1 when licensed. Text label "Microsoft Teams" is allowed. |
| `notion.svg` | Notion "N" block | theme-aware: white tile + black N (light), black tile + white N (dark) | Monochrome only. No gradients/shadows. Trademark of Notion Labs, Inc. |
| `gmail.svg` | Gmail "M" envelope, full color | white tile only | Colors `#4285F4` `#34A853` `#FBBC04` `#EA4335` `#C5221F`. Never single-color. |
| `github.svg` | GitHub Invertocat (`mark-github-16`) | white tile, `currentColor` (black/white) | Black on light, white on dark. Octicons MIT, mark trademarked (`GITHUB®`). Use for the Copy-Markdown row. |
| `link.svg` | Generic link (Lucide) | surface tile | No brand constraints. Copy-URL row. |

## Flowline product brand (first-party)

Source: `brand/index.html` — Flowline Brand Guidelines v1.0 (October 2026).
Canonical tokens: `flowline-tokens.json` (colors, type, radii, spacing, motion,
logo, icons, asset specs). Swift mirrors: `FlowlineTokens.swift` (primitives +
semantics), `FlowlineIcons.swift` (vectors), `WebDocTheme.swift` (CSS vars).

| Path | Contents | Rule |
|---|---|---|
| `flowline-tokens.json` | colors `#F7F7F5`/`#FFFFFF`/`#1D1D1F`/`#6E6E73`/`#E5E5E2`/`#EDEDEA`/`#3478F6`/`#FFB340`, type scale, radii 8/12/16, 4pt spacing | Single source — Swift/CSS must match these hexes. Amber = user action, blue = selection, never swapped. |
| `flowline/icons/mark.svg` | Logomark `M4 18h5v-5h6V8h5`, 24-grid, stroke 2.25, round caps | Never stretch/recolor/effects/rotate. Min 16px. |
| `flowline/icons/*.svg` (13) | Lucide official (ISC): focus, list, file-text, circle-dot, list-checks, upload, book-open, folder, search, check, chevron-right, rotate-ccw, mouse-pointer-2 — stroke adapted 2→1.75 | 24-grid, round, `currentColor`. Min 16px. `folder-solid` = official folder + 0.12 fill (DMG). Logomark `mark.svg` is custom (no official equivalent). |
| `flowline/dmg-dunes-land.jpg` | RETIRED — photo grounds violate brand §06 (flat canvas only). Kept on disk, unreferenced. | Do not use in new surfaces. |
| `platform/macos/Assets/AppIcon-*.png` + `.iconset/` + `.icns` | App icon masters from `tooling/release/generate_app_icon.py` | 1024 master, mark 56%, light canvas + hairline / dark ink. No pre-applied mask. |
| `platform/macos/Assets/dmg/background*.png` | DMG 540×400 @2x from `tooling/release/generate_dmg_background.py` | Photo + brandline / drag row / instruction. Finder slots (150,210)+(390,210), icon 120. |

## Sync rule

`platform/macos/Sources/FlowlinePublishing/WebDocIcons.swift` mirrors the
Share-menu files as Swift string constants (build-time inline — the web export is a
single self-contained HTML file, so it cannot fetch `shared/` at runtime).
When updating an SVG here, paste the same inner markup into the matching
`WebDocIcons.*` constant and keep `manifest.json` colors in sync.

`platform/macos/Sources/Flowline/UI/Flowline/FlowlineIcons.swift` (`FlowlineIconSVG`)
mirrors `flowline/icons/*.svg` the same way for the Flowline set.

Verification: `tooling/ci/check_brand_assets.sh` diffs both SVG sets against
their Swift constants, and checks `flowline-tokens.json` hexes against
`FlowlineTokens.swift` / `WebDocTheme.swift`.
