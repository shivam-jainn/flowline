# templates/ — guide-mode plugin catalogue (DATA ONLY)

One subfolder per guide mode: `standard`, `checklist`, `sop`, `tutorial`,
`runbook`, `presentation`, `reference`. Each folder is a template plugin:

- `manifest.json` — the plugin descriptor: `{id, version, label, copy,
  theme, synthesisStyle, quirks[]}`. Validated by
  `shared/contracts/template.schema.json`.
- `preview.md` — a short hand-checked snippet showing how step text looks
  in that mode (the same strings `TemplateRenderer` produces).

Rules:

- **No code here.** No `.swift` / `.rs` / executable files — data only
  (enforced by `tooling/ci/check_architecture.sh`, rule 10). Render logic
  lives in `platform/macos/Sources/FlowlineTemplates/` (Swift) and
  `core/crates/flowline_templates/` (Rust); both are pure functions over
  `Step`/`StepSession` and must stay byte-identical.
- Render rules per mode (`TemplateRenderer.renderStep`):
  - `standard` — `Step N: <description>`.
  - `checklist` (`checklist-markers`) — `- [ ] Step N: <description>`.
  - `sop` (`numbered-steps`) — `N. <description>`.
  - `tutorial` (`guidance-notes`) — title plus a `(<app> · <window>)`
    context line, plus a `Tip: <userNotes>` line when notes exist.
  - `runbook` (`code-fence`) — title plus the `textBlob` as a fenced code
    block (language from `codeLanguage`, defaulting to `bash` for code),
    plus a `Keys: <hotkeyCombo>` line when present.
  - `presentation` (`uppercase-titles`) — title uppercased (fixed POSIX
    locale, so output never depends on the user's locale).
  - `reference` (`target-line`) — title plus
    `<verb> → <target> · <app>`.
  - Unknown template ids fall back to `standard`.
- Expected outputs for a fixed 3-step session live in
  `shared/goldens/templates.sample.json` (both suites assert against it).
- `theme` is a `FlowlineIR.ThemeName` raw value; `synthesisStyle` is a
  `FlowlineAIGateway.DocumentationStyle` raw value. The id/label/copy/theme/
  style mappings mirror `FlowlineGuideMode` (track 2 owns the UI; this
  folder owns the data).

## Per-template quirks

What makes each mode's text preview visibly different, and where it is
pinned. Quirk ids are the `quirks[]` values in each `manifest.json`.

| Mode | Quirk id | Visible effect | Pinned by |
| ---- | -------- | -------------- | --------- |
| standard | — (fallback) | Plain `Step N:` titles | `preview.md`, `guide-preview.sample.md` §1 |
| checklist | `checklist-markers` | `- [ ]` box on every step | `preview.md`, `guide-preview.sample.md` §2, `PhaseR11GuidePreviewTests` |
| sop | `numbered-steps` | `N.` prefix, no titles | `preview.md`, `guide-preview.sample.md` §3 |
| tutorial | `guidance-notes` | `(app · window)` context line + `Tip:` notes | `preview.md`, `guide-preview.sample.md` §4 |
| runbook | `code-fence` | Fenced `textBlob` + `Keys:` combo line | `preview.md`, `guide-preview.sample.md` §5, `PhaseR11GuidePreviewTests` |
| presentation | `uppercase-titles` | Uppercased titles (POSIX locale) | `preview.md`, `guide-preview.sample.md` §6 |
| reference | `target-line` | `verb → target · app` line per step | `preview.md`, `guide-preview.sample.md` §7, `PhaseR11GuidePreviewTests` |
