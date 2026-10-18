# Instruments recipe: Flowline gutter drag-and-drop

Measures jitter in the gutter's DnD path: `NSTrackingArea mouseMoved` →
`updateProximity`, `GeometryReader` + `PreferenceKey` resolves
(`InsertMidXKey`, `CardFrameKey`), `ScrollViewReader.scrollTo` on
`dropTarget` change, `NSScrollView` edge-nudge (16pt / 0.09s), Force Touch
haptics. Signposts come from `FlowPerfLog` (subsystem
`com.flowline.app`); the on-screen HUD comes from `.gutterProbe()`.

## 1. Template

1. Xcode: **Product > Profile** (⌘I). This builds the Profile action —
   for release-representative numbers, set the Profile action's build
   configuration to **Release** (Scheme > Edit Scheme > Profile > Build
   Configuration) and re-enable logging via step 2.
2. Template chooser: start from **SwiftUI**.
3. Verify the track list contains **Time Profiler**, **Points of Interest**,
   and **Hitches**. Missing any? **Library (+)** > drag it in.
   - Time Profiler: where main-thread time goes during a drag.
   - Points of Interest: the `com.flowline.app` signpost lanes
     (`DragSession`, `TargetFlip`, `ProximityResolve`, `ScrollNudge`).
   - Hitches: scroll/drag hitch rate — the ground truth for "jitter".

## 2. Enable logging

DEBUG builds log by default. To force it on/off regardless of build config,
pass a launch argument (needs no bundle ID, works under Profile too):

- Scheme > Edit Scheme > **Profile** > Arguments > Arguments Passed On Launch:
  `-FlowlinePerfLogging YES` (or `NO` to silence).
- Alternative: `defaults write <app-bundle-id> FlowlinePerfLogging -bool YES`.
- Runtime/lldb: `e FlowPerfLog.setEnabled(true)`.

Attach the HUD (DEBUG only): add `.gutterProbe()` at the gutter root
(see `PROVIDER_NOTES.md`). **Remove it before capturing final numbers** —
the overlay's own per-frame sampler pollutes the FPS reading it displays.

## 3. Recording script (~60s)

1. Hit record in Instruments; focus the app.
2. **Slow pass:** drag one card across all gaps, ~1 card/sec, drop it.
3. **Fast pass:** drag a card back and forth across the full gutter width
   for ~10s (this stresses target flips + `scrollTo` follow).
4. **Edge-nudge:** hold a dragged card within ~72pt of the left edge for 3s,
   then the right edge for 3s (16pt nudges, throttled at 0.09s).
5. **Drops:** drop 3 cards (midline rule), including one drop while nudging.
6. Stop recording.

Optional Console correlation while reproducing outside Instruments:

```sh
log stream --predicate 'subsystem == "com.flowline.app"' --level debug
```

## 4. What good looks like

| Signal | Where | Pass |
|---|---|---|
| Proximity resolve | HUD "last resolve" / `proximity` log | **< 8ms** per resolve |
| Target flips | HUD "flips/s" / `TargetFlip` events | **< 2 flips per 100ms** (< ~20/s sustained) |
| Hitches | Hitches instrument, hitch-time-rate during drag | **zero hitches > 16ms** (1 frame @60Hz) |
| Frame p95 | HUD "p95" | **< 16.7ms** |
| Resolve CPU | Time Profiler, `updateProximity` + PreferenceKey reduce | not the hotspot — render/layout should dominate |

Fail patterns: resolve > 8ms → PreferenceKey churn (see `onPreferenceChange`
dedup guards); flip bursts → `dropUpdated` re-fire without the
`lastTarget` guard; hitches with idle main thread → `scrollTo` fighting the
pixel nudge (check the >1-card / 1.0s peace rule).

## 5. Export + PRs

1. Instruments: **File > Save** → `gutter-<date>-<build>.trace`.
2. Attach the `.trace` to the PR (Files tab or a linked artifact) and paste
   this block into the PR body with your numbers:

```md
## Gutter perf (Instruments)
- trace: <link>
- proximity resolve p50/max: __ms / __ms (budget <8ms)
- target flips/s sustained: __ (budget <20)
- hitches >16ms during drag: __ (budget 0)
- frame p95: __ms (budget <16.7)
```
