# "Open in" editor icons

Brand PNGs for the `EditorTarget` handoff row (`Sources/Flowline/UI/Flowline/Automation/`).
`EditorIconView` probes `NSImage(named: target.assetName)` → `alternateAssetName` →
SF-Symbol fallback, so when these files reach the app bundle's `Resources/`
directory they light up with **no code change** (`OpenInButtons.swift:42-46`).

Expected names (must match `EditorTarget.assetName`, `EditorTarget.swift:31-40`):

| File | Target | Size |
|---|---|---|
| `Cursor.png` | `.cursor` → `"Cursor"` | 512×512, ~28 KB |
| `VSCode.png` | `.vscode` → `"VSCode"` | 512×512, ~58 KB |
| `Xcode.png` | `.xcode` → `"Xcode"` | 512×512, ~124 KB |
| `Zed.png` | `.zed` → `"Zed"` | 1646×1646, ~160 KB |
| `SublimeText.png` | `.sublime` → `"SublimeText"` | 512×512, ~39 KB |
| `Nova.png` | `.finder` alias → `"Nova"` (`alternateAssetName`, `EditorTarget.swift:43-48`) | 512×512, ~185 KB |

There is intentionally **no `Finder.png`**: the Finder/terminal row uses the
SF-Symbol fallback (`folder.fill`), or at runtime
`NSWorkspace.shared.icon(forFile: "/System/Applications/Finder.app")` — no
redistribution involved.

## Source + license/usage note per icon

All artwork below is the vendor's own shipping app icon (extracted from the
vendor's `.icns`, or the vendor's official brand page). Displayed at 22pt in an
"Open in \<app\>" button that launches the user's own installed copy — i.e.
nominative identification, unmodified. Do not alter, recolor, or combine these
into the Flowline logo, and do not imply vendor endorsement.

- **Cursor.png** — extracted from the locally installed
  `/Applications/Cursor.app/Contents/Resources/Cursor.icns` (the actual
  shipping Cursor app icon, converted with
  `sips -s format png … -z 512 512`). Canonical brand source:
  <https://cursor.com/brand> ("Download brand assets" zip: 2D/2.5D logos, app
  icons, avatars). Rule: refer to the product as "Cursor" (not "Cursor AI" /
  "Cursor Code"); use assets unmodified.
- **VSCode.png** — extracted from
  `/Applications/Visual Studio Code.app/Contents/Resources/Code.icns`
  (`sips` → 512×512). Brand rules: <https://code.visualstudio.com/brand>.
  Notes: use the blue stable icon (never green Insiders / orange); label
  actions exactly "Open in VS Code"; icon use is approved for linking to /
  identifying VS Code, not for promoting your own product or implying
  Microsoft endorsement. Icon pack (PNG+SVG) also at
  `https://code.visualstudio.com/assets/branding/visual-studio-code-icons.zip`.
- **Xcode.png** — extracted from
  `/Applications/Xcode.app/Contents/Resources/Xcode.icns` (`sips` → 512×512).
  ⚠️ Highest-risk asset: Apple's third-party trademark guidelines
  (<https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html>)
  state Apple-owned graphic symbols/logos/icons may **not** be used without an
  express written license, and depictions must not imply endorsement. Before
  shipping, either obtain clearance, drop this file (the `hammer.fill`
  SF-Symbol fallback renders automatically), or switch this row to a runtime
  `NSWorkspace` icon lookup (no redistribution — see below).
- **Zed.png** — downloaded from the official brand page <https://zed.dev/brand>,
  "App icon → stable" PNG
  (`https://zed.dev/_next/static/media/stable-app-logo.0lgsg40_u_1r5.png`,
  1646×1646 as shipped). "The Zed name and logos are trademarks of Zed
  Industries, Inc." — no use implying official connection/endorsement and no
  merchandise without written consent.
- **SublimeText.png** — downloaded from the vendor's own site
  `https://www.sublimehq.com/images/sublime_text.png` (512×512 as shipped; no
  public brand kit found — <https://www.sublimetext.com> is the brand home).
  Trademark of Sublime HQ Pty Ltd; used here unmodified for app
  identification only.
- **Nova.png** — extracted from the official trial download
  <https://download.panic.com/nova/Nova-Latest.zip>
  (`Nova.app/Contents/Resources/Nova.icns`, `sips` → 512×512; no public press
  kit found — <https://nova.app> is the brand home). "Nova is a registered
  trademark of Panic."; use unmodified.

No manual-fetch gaps: all six files are present. To re-extract after an app
update, repeat the `sips` command above against the installed `.app`.

## Bundling + loading (nothing wired yet — build files untouched)

Current state: `platform/macos/Package.swift` declares **no** `resources` on any
target, and `tooling/release/bundle_app.sh` copies only `AppIcon.icns` plus the
fixture tree into `Contents/Resources/`. These PNGs live outside every target
path, so pick one option:

**Option A — recommended (matches the existing `AppIcon.icns` pattern).**
Append to the "Copy Icon" section of `tooling/release/bundle_app.sh`
(after the `AppIcon.icns` block, ~line 90):

```bash
# 4b. Copy "Open in" editor icons (platform/macos/Assets/Editors/*.png)
for icon in Cursor VSCode Xcode Zed SublimeText Nova; do
    if [ -f "${ROOT_DIR}/platform/macos/Assets/Editors/${icon}.png" ]; then
        cp "${ROOT_DIR}/platform/macos/Assets/Editors/${icon}.png" "${RESOURCES_DIR}/${icon}.png"
    fi
done
```

Loading stays exactly as written: `NSImage(named: target.assetName)`
(`OpenInButtons.swift:43`) resolves main-bundle `Resources/` images by name
(without extension) and picks HiDPI variants automatically. No `Bundle.module`
involved — that API only addresses SwiftPM resource bundles (see Option B).

**Option B — SwiftPM resources instead (requires moving the files).**
Copy `Assets/Editors/*.png` into the executable target (e.g.
`Sources/Flowline/Resources/Editors/`), then declare them:

```swift
.executableTarget(
    name: "Flowline",
    dependencies: ["FlowlineFixtures"] + coreModules,
    path: "Sources/Flowline",
    resources: [.copy("Resources/Editors")]
),
```

and load via the SPM bundle, **not** `NSImage(named:)`:

```swift
if let url = Bundle.module.url(forResource: "Cursor", withExtension: "png",
                               subdirectory: "Editors"),
   let image = NSImage(contentsOf: url) { … }
```

`NSImage(named:)` does **not** search `Bundle.module`; `Bundle.module` does
**not** see files copied by `bundle_app.sh`. Use `NSImage(named:)` with
Option A, `Bundle.module` with Option B — never mix.

Safer runtime alternative (avoids redistributing third-party marks entirely):
ask the OS for the installed app's icon and fall back to the bundled PNG:

```swift
let ws = NSWorkspace.shared
let icon = ws.icon(forFile: ws.fullPath(forApplication: "Cursor") ?? "")
    ?? NSImage(named: target.assetName)
```

## Verification

`ls` only (per task constraints — no build files touched, no `swift build` run):

```bash
ls -la platform/macos/Assets/Editors/
```
