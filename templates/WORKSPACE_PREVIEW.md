# Workspace preview — split visual/text UX

One-page overview of the Flowline workspace preview. Implementation lives
in `platform/macos/Sources/Flowline/UI/Flowline/` (track 2 owns
`FlowlineEditor.swift` layout) and the renderers in
`platform/macos/Sources/FlowlineTemplates/` (track 1) — this doc explains
the shape so reviewers and template authors know where things go.

## The split

The Preview (`FlowlineEditor.swift`, `fullPreviewSheet`) shows the same
`StepSession` two ways side by side:

- **Left — visual:** the step's captured media with its halo mark
  (`FlowlineStage.swift` + `FlowlineHaloResolver` in `FlowlineModels.swift`).
  Amber halo = user interaction, never editor state.
- **Right — text preview:** the mode-specific projection produced by
  `TemplateRenderer.renderGuide` (`FlowlineTemplates/TemplateRenderer.swift`).
  Same steps, different words per template. Expected text for the 3-step
  golden session is pinned in `shared/goldens/guide-preview.sample.md`.

The mode pill row (`FlowlineGuideMode.allCases` in `FlowlineModels.swift`)
switches the right pane only; the step model never forks.

## Template plugin model

Modes are presentation-only views over one step model. One template =
one folder in `templates/<mode>/` (data only):

- `manifest.json` — `{id, version, label, copy, theme, synthesisStyle,
  quirks[]}` descriptor (mirrors `GuideTemplate` in
  `FlowlineTemplates/GuideTemplate.swift`).
- `preview.md` — hand-checked snippet of what step text looks like in
  that mode (the same strings `TemplateRenderer` produces).

The 7 built-ins (`standard`, `checklist`, `sop`, `tutorial`, `runbook`,
`presentation`, `reference`) are declared in `GuideTemplate.all`,
resolved without singletons via `TemplateRegistry.withDefaults()`, and
rendered by the pure, Foundation-only `TemplateRenderer` (unknown ids
fall back to `standard`). Per-mode quirks (checkboxes, runbook fences,
target lines, uppercased titles) are tabled in `templates/README.md`.

## Adding a new template

1. **Manifest** — add `templates/<mode>/manifest.json` + `preview.md`,
   and the matching `GuideTemplate` entry (`label`, `copy`, `theme`,
   `synthesisStyle`, `quirks[]`) plus the `TemplateRenderer.renderStep`
   branch. `FlowlineGuideMode` (track 2) mirrors the UI side.
2. **Golden + test** — append the mode's section to
   `shared/goldens/guide-preview.sample.md` (3-step golden session) and
   extend `platform/macos/Tests/FlowlineTests/DataLine/PhaseR11*` with the
   mode's quirk assertion. No `.swift`/`.rs` under `shared/` or
   `templates/`.

## File paths

| What | Where |
| ---- | ----- |
| Mode enum + copy + theme/style maps (UI) | `platform/macos/Sources/Flowline/UI/Flowline/FlowlineModels.swift` |
| Split workspace + Preview panes | `platform/macos/Sources/Flowline/UI/Flowline/FlowlineEditor.swift` |
| Visual stage + gutter | `.../Flowline/FlowlineStage.swift`, `.../Flowline/FlowlineGutter.swift` |
| Template data + quirks table | `templates/` (`templates/README.md`) |
| Template structs + registry + renderer | `platform/macos/Sources/FlowlineTemplates/` |
| Preview golden (7 modes × 3 steps) | `shared/goldens/guide-preview.sample.md` |
| Canonical session golden | `shared/goldens/session.sample.json` |
| Markdown projection | `platform/macos/Sources/FlowlinePublishing/MarkdownExporter.swift` |
| Preview tests | `platform/macos/Tests/FlowlineTests/DataLine/PhaseR11*` |
