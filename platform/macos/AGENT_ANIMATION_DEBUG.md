# Flowline Gutter — Animation / DnD Jitter Debug Playbook (macOS 14 only)

> Scope: `platform/macos/Sources/Flowline/UI/Flowline/FlowlineGutter.swift` drag-to-reorder
> and proximity-insert path. No new dependencies. macOS 14 APIs only.
>
> Checked 2026-10-18: no `AGENTS.md` / `AGENT.md` / `CLAUDE.md` and no
> `platform/macos/*.md` animation guide exists, so this file is the canonical
> playbook (not a duplicate). It complements — does not replace:
>
> - [platform/macos/README.md](README.md) — package layout (all Swift lives here)
> - [../../README.md](../../README.md) — `make build` / `make test` / `make check-arch`
> - [../../docs/PLAN.md](../../docs/PLAN.md) — architecture and roadmap
> - [../../docs/roadmap/](../../docs/roadmap/) — per-phase exit gates
>
> Convention: all code references are `FlowlineGutter.swift:<line>` unless
> another file is named. `cardWidth = 148` lives in
> `Sources/Flowline/UI/Flowline/FlowlineTokens.swift:242`.

---

## 1. Symptom triage — jitter vs stutter vs lag vs flicker

Watch the gutter (horizontal step strip) during a drag. Classify FIRST —
each symptom points at a different lane. Do not profile until classified.

| Symptom | What it looks like in the gutter DnD | First lane to check | Second lane |
|---|---|---|---|
| **Jitter** (high-frequency shake, ±1–3px at 30–60Hz) | Dragged card or drop-target bar vibrates while pointer is steady; sibling gap opens/closes rapidly | **Proximity resolve** — `updateProximity(x:)` (`FlowlineGutter.swift:145`) + stickiness bias (`:196`); border dithering between two gaps | `GutterMouseTracker.mouseMoved` (`:455`) firing unthrottled; identical-X re-resolves |
| **Stutter** (frames drop in bursts, motion freezes then jumps) | Sibling glide (`FlowMotion.shift`) freezes mid-glide, then snaps; scroll-follow jumps in chunks | **PreferenceKey churn** — `InsertMidXKey` (`:375`) + `CardFrameKey` (`:397`) re-emitting per frame; `onPreferenceChange` (`:88`,`:92`) invalidating the whole `HStack` | **Shadow/overlay recompute** — triple `.shadow` in `GutterCard` (`:546–549`) + stacked `.animation` (`:553–559`) re-evaluating per state flip |
| **Lag** (smooth but trails pointer by 100ms+) | Drop-target highlight and leading gap (`:278`) arrive late behind the cursor; `dropUpdated` pump feels drunk | **`scrollTo` fights** — selection-follow (`:99–104`) vs drag-follow (`:105–111`) vs `companion.nudge` (`:643`) all moving the scroll view | `withAnimation` at every mutation site instead of one transaction; `proxy.scrollTo` re-animating on every `dropTargetID` set (`:307`) including repeats |
| **Flicker** (insert `+` slot or bar flashes on/off) | `ProximityInsert` (`:469`) width 0→30 pops in/out at gap borders; drop-target bar (`:537–544`) blinks | **Slot-growth feedback loop** — trigger anchored to slot center instead of card edges; verify zone math (`:175–193`) and `endPad = 36` (`:142`) | Conditional layout changing width during drag — `.padding(.leading, … gapWidth)` (`:278`) + `.frame(width: near ? 30 : 0)` (`:492`) interacting |

Quick discriminators:

- **Jitter stops when you hold the pointer still** → proximity/throttle lane (§5a).
- **Stutter shows in Instruments as View Body spikes, pointer still or moving** → PreferenceKey/shadow lane (§5b, §5e).
- **Lag scales with session length (worse at 12 steps than 3)** → per-card readers (`InsertMidReader` `:382`, `CardFrameReader` `:404`) × N, and `scrollTo` per event (§5b, §5f).
- **Flicker only at gap borders, never mid-card** → zone/stickiness lane (§5a + zone comment `:127–143`).
- **Haptic tick repeats while pointer rests on one card** → `companion.lastTarget` guard (`:303–306`) broken; fix before profiling (it masks the real signal).
- **Only on trackpad / only on mouse** → note input device and re-run repro (§2); Force Touch haptics (`GutterHaptics` `:602–606`) fire on trackpads only.

---

## 2. Repro protocol — fixed setup, scripted drag, per-run record

Do this identically every run. Any deviation invalidates before/after compares.

### 2.1 Fixed setup

- **Build:** `make build` from repo root (never bare `swift build` on clean checkout — FFI first). Record the git SHA.
- **Config:** Release (`--configuration release` via the bundled `Flowline.app`; see `make test-dev` in `Makefile`). Debug overlays and `-Onone` hide or exaggerate hitches — never gate on a Debug build.
- **Window:** 1320×840, Flowline editor open, gutter visible without horizontal scroll at start.
- **Fixture session:** 12 steps (covers interior gaps + both end gaps + edge-nudge range). Use the fixture generator path (`FlowlineFixtures/DemoSessionGenerator.swift`) or a recorded 12-step session; record which.
- **Input device:** run once with mouse, once with trackpad. Label every trace/log with the device.
- **Reduce Motion:** run with OFF (default), then one confirmatory run with ON (System Settings → Accessibility → Display → Reduce Motion). Gutter gates scale/offset/gap on `reduceMotion` (`FlowlineGutter.swift:38,278,524,564`) — ON must show opacity-only motion and no gap growth.

### 2.2 30-second scripted drag

Use step 6 (middle card) as the dragged card so both scroll directions are reachable:

1. **5 slow passes** (~4s each = 20s): drag left→right across all 12 cards at ~1 card/sec. Pause ~0.5s over cards 3, 6, 9. Watch for jitter (steady-pointer shake) and flicker (gap-border flashing).
2. **2 fast flicks** (~2s each = 4s): fling right→left and left→right at full speed. Watch for lag (highlight trailing) and stutter (snap jumps).
3. **1 edge-hold** (~6s): hold the dragged card within 72pt of the trailing edge (`GutterDragCompanion.edgeInset`, `FlowlineGutter.swift:616`) for 6s. Watch the 16pt/0.09s nudge pump (`:617–618, :643–665`): it must step smoothly, never fight the spring scroll-follow (`:105–111`).

### 2.3 What to record each run

Copy this block into the PR / trace notes:

```text
SHA:            <git rev-parse --short HEAD>
Build:          release | debug (gate only on release)
Window:         1320x840
Steps:          12 (fixture: <name>)
Input:          mouse | trackpad
Reduce Motion:  off | on
Run:            slow-passes | flicks | edge-hold | full-30s
Result:         pass | jitter | stutter | lag | flicker (+ card index / gap index)
Trace:          docs/traces/<name>.trace (see §4)
Log excerpt:    <5-line Console slice showing signposts, see §3>
```

---

## 3. Logging workflow — `FlowlinePerfLogging` + signposts

### 3.1 Enable

Standard flag (UserDefaults + env override so CI and manual runs share one knob):

```bash
# One-shot for this launch (preferred — never commits a dirty default):
FLOWLINE_PERF_LOGGING=1 swift run --package-path platform/macos flowline app

# Or persist locally while iterating (remember to delete before PR):
defaults write com.flowline.macos FlowlinePerfLogging -bool YES
# Disable when done:
defaults delete com.flowline.macos FlowlinePerfLogging
```

Precedence: env var wins when set (`FLOWLINE_PERF_LOGGING=0` forces off even if
the default is YES). Gate all per-event logging behind the flag — logging must
be zero-cost when off (no string interpolation on the drag path).

### 3.2 Where logs go

- **Subsystem:** `com.flowline.app`, category `drag`.
- **View:** Console.app → subsystem `com.flowline.app`, or streaming:
  ```bash
  log stream --predicate 'subsystem == "com.flowline.app"' --level debug
  ```
- **Signposts:** bracket every drag session so traces and logs correlate:
  - `dragSession` begin/end — from `.onDrag` lift (`FlowlineGutter.swift:290–296`) through `performDrop` (`:583–594`) or drag-cancel (`session.steps.count` reset, `:112–118`).
  - `proximityResolve` — around `updateProximity(x:)` (`:145–203`).
  - `targetChange` — only when `dropTargetID` actually changes (`:307`), NOT on repeat `dropUpdated` pumps.
  - `scrollFollow` vs `nudge` — distinguish `proxy.scrollTo` (`:101–110`) from `companion.nudge` (`:643`).

### 3.3 Example excerpts (what healthy vs sick looks like)

Healthy — one resolve per distinct X, one target change per card, throttled nudges:

```text
[drag] dragSession begin id=step-06 device=mouse
[drag] proximityResolve x=412.0 -> gap=5 (1.1ms)
[drag] targetChange nil -> step-07 (haptic=alignment)
[drag] scrollFollow slot-step-07 anchor=center
[drag] proximityResolve x=412.0 skipped (identical X)
[drag] nudge dx=+16.0 visibleMax=598.0 (throttled 90ms)
[drag] dragSession end id=step-06 target=step-09 settle=spring(0.28/0.86)
```

Jittery — identical-X re-resolves, per-event target re-sets, scroll fight:

```text
[drag] dragSession begin id=step-06 device=mouse
[drag] proximityResolve x=412.0 -> gap=5 (3.8ms)   # <-- >2ms: PreferenceKey storm?
[drag] proximityResolve x=412.0 -> gap=6 (3.9ms)   # <-- identical X re-resolved + flipped: stickiness broken?
[drag] targetChange step-07 -> step-07 (re-set!)   # <-- missing lastTarget guard: expect haptic spam
[drag] scrollFollow slot-step-07 + nudge dx=+16.0 same frame  # <-- fight: suppress one (§5f)
[drag] proximityResolve x=412.0 -> gap=5 (4.1ms)   # <-- dithering 5/6/5: zone math (§5a)
```

Rule of thumb: any `proximityResolve` consistently >2ms, any `targetChange`
where old == new, or any frame containing both `scrollFollow` and `nudge`
means stop and fix (§5) before re-profiling.

---

## 4. Instruments workflow — template, lanes, thresholds, trace files

### 4.1 Template and recording

1. Open `Flowline.app` (Release, `make test-dev` fresh bundle so PID/start time confirm freshness).
2. Instruments → **SwiftUI** template (includes View Body, View Properties, Time Profiler, Hitches). macOS 14 only — do not use the older Cocoa Layout template; SwiftUI body attribution is what matters here.
3. Target → Flowline, record options: 30s window.
4. Run the §2.2 scripted drag (5 slow + 2 fast + 1 edge-hold) while recording.
5. Stop, then filter the timeline to the `dragSession` signpost interval (§3.2) before reading numbers.

### 4.2 How to read the lanes

- **SwiftUI View Body** — each bar is a body evaluation. During a steady-pointer hold you expect ~zero `GutterCard`/`ProximityInsert` bodies. A solid wall of `CardFrameReader` / `InsertMidReader` bodies while the pointer is still = PreferenceKey feedback loop (§5b). Click a spike → Extended Detail → view identity confirms which card/gap.
- **SwiftUI View Properties** — shows which state change invalidated the view. `insertMids` / `cardFrames` flipping every frame = keys re-emitting; `dropTargetID` flipping between two values = border dither; `draggingID` stable + bodies still firing = mouseMoved/proximity lane, not state lane.
- **Time Profiler (main thread)** — sort by weight inside the `dragSession` interval. Expect `updateProximity` + layout under a few percent. Red flags: `resolvePreferences` / `updateViewGraph` dominating (key storm), `shadow` / `renderShadow` / `offscreenPass` (shadow lane), `scrollTo` / `scrollRectToVisible` re-entrancy (scroll-fight lane).
- **Hitches** — the scroll/drag hitch track. Any red hitch marker inside `dragSession` is a fail (see thresholds). Correlate its timestamp with the log excerpt (§3.3) to name the cause.

### 4.3 Hitch threshold table (gate numbers)

| Metric | Pass | Investigate | Fail |
|---|---|---|---|
| Hitch (>16.7ms frame) during `dragSession` | 0 | 1 (explain + re-run) | ≥1 unexplained |
| p95 frame time, drag interval | ≤8ms | 8–12ms (note lane + fix) | >12ms |
| p95 `proximityResolve` (log) | ≤1ms | 1–2ms | >2ms sustained |
| `GutterCard` bodies per second, pointer held still | ~0 | <10/s | ≥10/s sustained |
| `targetChange` old == new (log) | 0 | — | ≥1 |
| Edge-hold nudge cadence | 1 step / 90ms (11/s) | bursts | continuous + `scrollFollow` same frame |

> 60fps budget is 16.7ms; the >16ms hitch line and the >12ms p95 line leave
> headroom for compositor + display-link variance on macOS 14.

### 4.4 Saving traces

```bash
mkdir -p docs/traces   # gitignored except .gitkeep + referenced traces
```

Naming: `docs/traces/<date>-gutter-<run>-<device>-<motion>.trace`

- `<date>` = `YYYYMMDD`, `<run>` = `slow5|flick2|edgehold|full30s`,
  `<device>` = `mouse|trackpad`, `<motion>` = `rm-off|rm-on`.
- Example: `docs/traces/20261018-gutter-full30s-mouse-rm-off.trace`
- Before/after pairs share everything except a `-before` / `-after-<fix>` suffix.
- Traces are large — commit only the gated pair referenced by the PR (§6); keep
  the rest local. Never commit a Debug-build trace as evidence.

---

## 5. Fix checklist — priority order for SwiftUI DnD jitter (macOS 14)

Work top-down. Re-run §2 + §3 after each item; stop at the first item that
moves the failing metric (§4.3). Do not stack speculative fixes.

### (a) Throttle `mouseMoved` / proximity — highest yield for jitter

- File: `GutterMouseTracker` (`FlowlineGutter.swift:418–463`) + `updateProximity` (`:145–203`).
- Skip identical X (`guard x != lastMouseX else { return }` — the log's `skipped (identical X)` line proves it works).
- Debounce to ~8ms or pace with `CADisplayLink` (available macOS 14+; no new dependency): coalesce `mouseMoved` events, resolve once per tick.
- Keep the stickiness bias (`:196`, `-2` toward armed gap) — it kills border dithering without delaying switches. If jitter persists at one border, widen bias before touching zone math.

### (b) Kill PreferenceKey storms — highest yield for stutter

- Files: `InsertMidXKey` (`:375–380`), `CardFrameKey` (`:397–402`), readers (`:382–392`, `:404–414`), sinks (`:88–93`).
- Aggregate into a **single** key emission per layout pass (one dict, not per-card events); make the value `Equatable` so identical frames don't invalidate; **do not publish per-frame mids while `draggingID != nil`** — freeze `insertMids`/`cardFrames` for the drag duration and resolve against the frozen snapshot (geometry doesn't meaningfully change mid-drag except the gap itself, which is a constant `14pt`).
- Verify: steady-pointer `View Body` rate must fall to ~0 (§4.3).

### (c) Stabilize layout — fixes flicker

- `cardWidth` is fixed at `148` (`FlowlineTokens.swift:242`) — keep it fixed; never derive card width from content during a drag.
- No conditional **width** changes on the drag path: prefer `.offset` for the sibling gap over `.padding(.leading)` (`:278`) if the padding pass itself re-triggers `CardFrameKey` (padding changes layout → new frames → new keys → new layout = loop). The gap constant stays `GutterDragCompanion.gapWidth = 14` (`:613`).
- Same for `ProximityInsert` (`:492`): if the 0→30 width animation feeds back into zone math, drive visibility with opacity/offset and reserve (or don't reserve) space unconditionally. Zone math must stay anchored to **card edges**, never slot centers (`:136–138`).

### (d) One `.animation` per state, at the mutation site

- `GutterCard` currently stacks six `.animation` modifiers (`:553–559`) plus per-value ones in `FlowlineEditor`/`FlowlineSidebar`. Collapse to one animation per driving value; prefer `withAnimation` **at the mutation site** (already the pattern for lift `:292`, hover `:307`, settle `:326`) or an explicit `.transaction`, over stacked view-level `.animation(_, value:)` that re-fire on unrelated changes.
- Gesture-driven visuals (lift, drop-target, sibling shift, settle) stay on springs (`FlowMotion.spring` / `.shift`, `FlowlineTokens.swift:306–312`, WWDC23 "Animate with springs" retarget rule); non-gesture flips stay on 150/220ms curves. Never mix both on the same value.

### (e) Shadow / rasterize — stutter's accomplice

- `GutterCard` stacks **three** `.shadow` modifiers (`:546–549`) evaluated per state flip (hover/select/drag). During drag: drop to zero/one shadow (`.shadow(radius: 0)` when `draggingID != nil`), restore on settle.
- `drawingGroup` (rasterize) **only** on the drag preview (`GutterDragPreview` `:685–714`), never on the live card row — flattening the row forces full re-raster per sibling shift.
- Preview itself stays lightweight (see (h)) — rasterizing a heavy preview just moves the cost.

### (f) Scroll-follow vs nudge fights — fixes lag + edge stutter

- Two movers exist: `proxy.scrollTo` follow (`:99–111`) and `companion.nudge` pixel steps (`:643–665`, 16pt / 0.09s, 72pt inset). While `companion` nudge is active (edge-hold), **suppress the `dropTargetID` → `scrollTo`** (`:105–111`); while a spring `scrollTo` is in flight, skip nudge steps. Log both with distinct signposts (§3.2) so same-frame co-occurrence is visible.
- Guard `onChange(of: dropTargetID)` with old-vs-new (skip `nil → nil` and `x → x`); every `scrollTo` must trace to a real target change.

### (g) Haptics off the critical path — verify, don't rework

- Already async-safe by design: `GutterHaptics.play` (`:602–606`) is a one-line `NSHapticFeedbackManager.defaultPerformer.perform(.now)` — silent no-op without Force Touch, never Reduce-Motion-gated (correct: haptics are not motion, `:17–19`).
- Verify only: (1) `companion.lastTarget` guard (`:303–306`, `:311`) so `dropUpdated` re-fires don't re-tick; (2) no haptic call inside `updateProximity` or any layout/PreferenceKey path; (3) `performDrop` plays `.generic` once (`:327`). If all three hold, move on — haptics are not your jitter.

### (h) Drag preview lightweight — no `GeometryReader` inside

- `GutterDragPreview` (`:685–714`) is already a static snapshot (number + title, fixed width, conditional shadow/scale) — keep it that way. Never add `GeometryReader`, `PreferenceKey`, image loads (`thumb(for:)` `:353–371` must NOT run in the preview), or animated content inside the preview: it renders under the drag pointer at full rate and any layout pass there multiplies the hitch.
- Reduce Motion renders it flat (`lifted: !reduceMotion`, `:295`); preserve that.

---

## 6. PR gate — numbers to paste, and when to say "needs another pass"

Paste this block in every gutter-motion PR. Missing lines = not reviewable.

```text
Build:        <release SHA, `make build` clean>
Gates:        `make check-arch` pass | `swift test --package-path platform/macos` 313+ tests pass (paste count)
Trace:        docs/traces/<before>.trace vs docs/traces/<after>.trace (naming per §4.4)
p95 frame:    before <N>ms -> after <M>ms (drag interval, SwiftUI template, §4.2)
Hitches:      before <N> -> after <M> (0 to pass, §4.3)
Bodies/s:     <N>/s steady-hold before -> <M>/s after (target ~0)
Fix applied:  §5(<letter>) <one line: what changed>
Repro:        §2.2 full-30s, mouse + trackpad noted, Reduce Motion off + on-confirm noted
```

Say **"needs another pass"** when ANY of these hold — no exceptions, no "close enough":

- Any unexplained hitch (>16ms) remains in the `dragSession` interval.
- p95 frame >12ms, or p95 `proximityResolve` >2ms sustained.
- Steady-hold body rate ≥10/s, or any `targetChange` with old == new in the log.
- Same-frame `scrollFollow` + `nudge` still present in the log.
- Gate run on a Debug build, wrong window size, wrong step count, or single-device-only testing.
- Trace files missing, misnamed, or from a different SHA than the PR.
- `make check-arch` or the 313+ Swift tests not both green.

---

## Quick-reference: file map

| Concern | Location |
|---|---|
| Gutter DnD + proximity + cards + haptics + nudge | `platform/macos/Sources/Flowline/UI/Flowline/FlowlineGutter.swift` |
| Motion tokens (`standardFast`, `spring`, `shift`) + `cardWidth = 148` | `platform/macos/Sources/Flowline/UI/Flowline/FlowlineTokens.swift` |
| Editor scroll/selection interplay | `platform/macos/Sources/Flowline/UI/Flowline/FlowlineEditor.swift` |
| Fixture sessions for §2.1 | `platform/macos/Sources/FlowlineFixtures/DemoSessionGenerator.swift` |
| Gates for §6 | `Makefile` (`build`, `test`, `check-arch`), `tooling/ci/check_architecture.sh` |
| Saved traces (create on first use) | `docs/traces/` (naming §4.4) |
