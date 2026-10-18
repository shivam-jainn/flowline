# Wire-up notes for the gutter-fix agent (copy-paste)

`FlowPerfLog` and `.gutterProbe` live in the **same target** (`Flowline`),
so **no import needed** — reference them directly from
`FlowlineGutter.swift`. All calls early-return when
`FlowPerfLog.isEnabled` is false (DEBUG default ON; Release default OFF,
launch-arg `-FlowlinePerfLogging YES` overrides either).

## 1. Time `updateProximity` (paste after `lastMouseX = x`)

Anchor: `updateProximity(x:)` throttle guards (~line 170-174).

```swift
        lastMouseX = x
        let __t0 = ContinuousClock().now
        defer {
            let el = ContinuousClock().now - __t0
            let ms = Double(el.components.seconds) * 1_000
                + Double(el.components.attoseconds) / 1e15
            FlowPerfLog.proximityResolve(durationMs: ms,
                gapCount: session.steps.count + 1)
        }
```

## 2. Target flips + drag session (paste into drop closures)

Anchor: `.onDrag` (~line 319) and `StepDropDelegate.onHover` (~line 328).

```swift
        .onDrag {
            withAnimation(FlowMotion.spring) { draggingID = s.id }
            FlowPerfLog.beginDrag(id: s.id)
            return NSItemProvider(object: s.id as NSString)
        } preview: {
```
```swift
                    if companion.lastTarget != s.id {
                        FlowPerfLog.updateTarget(from: companion.lastTarget, to: s.id)
                        companion.lastTarget = s.id
                        GutterHaptics.play(.alignment)
```

## 3. Drop apply (paste into the `onMove` closure, ~line 355)

```swift
                // Settle is gesture-driven: spring the reorder…
                let __drop = FlowPerfLog.signpostBegin("DropApply", .dnd)
                withAnimation(FlowMotion.shift) { onMove(from, to) }
                FlowPerfLog.signpostEnd("DropApply", .dnd, id: __drop)
                FlowPerfLog.endDrag(id: fromID, dropped: true)
                GutterHaptics.play(.generic)
```

## 4. Edge-nudge (paste into `GutterDragCompanion.nudge`, ~line 690)

```swift
        guard dx != 0 else { return }
        FlowPerfLog.scrollNudge(dx: dx)
        let docWidth = sv.documentView?.frame.width ?? visible.width
```

## 5. HUD overlay (paste after the `.animation(count)` line, ~line 146)

```swift
        .animation(FlowMotion.standard, value: session.steps.count)
        .gutterProbe() // DEBUG only; remove before final Instruments capture
```

## 6. Haptics (optional, inside `GutterHaptics.play`)

```swift
    static func play(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        FlowPerfLog.haptic("\(pattern)")
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
```
