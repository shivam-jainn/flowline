# Guide preview — golden session (3 steps)

Expected "how the text will look" output for each of the 7 guide modes,
rendered from the 3-step session in `shared/goldens/session.sample.json`
via `TemplateRenderer.renderGuide` (`platform/macos/Sources/FlowlineTemplates/`):

- Step 1: Click "Save" in Docs — Safari (Safari, `AXButton` "Save", 100,200)
- Step 2: Run "git status" in Terminal (Terminal, `textBlob: "git status"`)
- Step 3: Press ⌘S (Safari, hotkey `⌘S`)

Each section below is the exact `renderGuide` text for that mode's
`templates/<mode>/manifest.json` template (header + byline, then one
`renderStep` block per step). Deterministic: same session ⇒ same text.
`PhaseR11GuidePreviewTests` asserts every quirk shown here.

---

## 1. standard — "Visual and explanation for every Step."

Quirk: none — plain `Step N:` titles. This is the fallback for unknown
template ids.

```text
# Golden Session

_Standard guide_ — Visual and explanation for every Step.

Step 1: Click "Save" in Docs — Safari

Step 2: Run "git status" in Terminal

Step 3: Press ⌘S
```

## 2. checklist — "A tickable list of everything to do."

Quirk (`checklist-markers`): every step gets a `- [ ]` box. Ticking a box
marks progress only; the steps never change.

```text
# Golden Session

_Checklist_ — A tickable list of everything to do.

- [ ] Step 1: Click "Save" in Docs — Safari

- [ ] Step 2: Run "git status" in Terminal

- [ ] Step 3: Press ⌘S
```

## 3. sop — "Action-oriented structured instructions."

Quirk (`numbered-steps`): numbered steps, no `Step N:` prefix.

```text
# Golden Session

_SOP_ — Action-oriented structured instructions.

1. Click "Save" in Docs — Safari

2. Run "git status" in Terminal

3. Press ⌘S
```

## 4. tutorial — "More explanatory, written for a first run."

Quirk (`guidance-notes`): each step names where it happens
(`(app · window)`); author `userNotes` surface as `Tip:` lines when
present (this session has none).

```text
# Golden Session

_Tutorial_ — More explanatory, written for a first run.

Step 1: Click "Save" in Docs — Safari
  (Safari · Docs — Safari)

Step 2: Run "git status" in Terminal
  (Terminal · zsh)

Step 3: Press ⌘S
  (Safari · Docs — Safari)
```

## 5. runbook — "Step, command, expected result, verification."

Quirk (`code-fence`): steps with a `textBlob` render a fenced code block
(language from `codeLanguage`, defaulting to `bash` for code); hotkey
steps name their keys.

````text
# Golden Session

_Runbook_ — Step, command, expected result, verification.

Step 1: Click "Save" in Docs — Safari

Step 2: Run "git status" in Terminal
```bash
git status
```

Step 3: Press ⌘S
  Keys: ⌘S
````

## 6. presentation — "Large visuals with minimal text."

Quirk (`uppercase-titles`): titles render uppercased in a fixed POSIX
locale, so output never depends on the user's locale.

```text
# Golden Session

_Presentation_ — Large visuals with minimal text.

STEP 1: CLICK "SAVE" IN DOCS — SAFARI

STEP 2: RUN "GIT STATUS" IN TERMINAL

STEP 3: PRESS ⌘S
```

## 7. reference — "Compact, searchable summary."

Quirk (`target-line`): each step keeps its title plus a
`verb → target · app` line (`verb`/`target` mirror
`FlowlineHaloResolver`).

```text
# Golden Session

_Reference_ — Compact, searchable summary.

Step 1: Click "Save" in Docs — Safari
Click → Save · Safari

Step 2: Run "git status" in Terminal
Write → zsh · Terminal

Step 3: Press ⌘S
⌘S → Docs — Safari · Safari
```
