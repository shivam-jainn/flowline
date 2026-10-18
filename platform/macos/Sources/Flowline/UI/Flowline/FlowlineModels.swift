import Foundation
import FlowlineIR
import FlowlineAIGateway

/// Flowline guide modes — presentation only, one step model.
/// Port of `MODES` / `MODE_LABEL` / `MODE_COPY` in the prototype.
public enum FlowlineGuideMode: String, CaseIterable, Identifiable {
    case standard, checklist, sop, tutorial, runbook, presentation, reference
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .standard: return "Standard guide"
        case .checklist: return "Checklist"
        case .sop: return "SOP"
        case .tutorial: return "Tutorial"
        case .runbook: return "Runbook"
        case .presentation: return "Presentation"
        case .reference: return "Reference"
        }
    }
    public var copy: String {
        switch self {
        case .standard: return "Visual and explanation for every Step."
        case .checklist: return "A tickable list of everything to do."
        case .sop: return "Action-oriented structured instructions."
        case .tutorial: return "More explanatory, written for a first run."
        case .runbook: return "Step, command, expected result, verification."
        case .presentation: return "Large visuals with minimal text."
        case .reference: return "Compact, searchable summary."
        }
    }
    /// Maps onto the AI synthesis style (Flowline has 4 documentation styles).
    public var synthesisStyle: DocumentationStyle {
        switch self {
        case .standard, .tutorial, .sop, .checklist: return .sopGuide
        case .runbook: return .bugReport
        case .presentation: return .executiveSummary
        case .reference: return .automationScript
        }
    }
    /// Maps onto the export theme (Flowline has 3 themes).
    public var theme: ThemeName {
        switch self {
        case .sop, .runbook: return .enterpriseSop
        case .presentation: return .developerDark
        default: return .modernMinimal
        }
    }
}

/// Halo annotation kind — amber, marks user interaction, never editor state.
/// Port of `halo-click/spotlight/rect/callout/key/arrow/cursor` CSS + `haloFor()`.
public enum FlowlineHaloKind: String, Codable, CaseIterable {
    case click, spotlight, rect, callout, key, arrow, cursor

    public var label: String {
        switch self {
        case .click: return "Click"
        case .spotlight: return "Spotlight"
        case .rect: return "Rectangle"
        case .callout: return "Callout"
        case .key: return "Key"
        case .arrow: return "Arrow"
        case .cursor: return "Cursor"
        }
    }
    public var systemImage: String {
        switch self {
        case .click: return "circle.dashed"
        case .spotlight: return "lightbulb"
        case .rect: return "rectangle.dashed"
        case .callout: return "text.bubble"
        case .key: return "keyboard"
        case .arrow: return "arrow.up.right"
        case .cursor: return "cursorarrow"
        }
    }
}

/// Resolved halo for a step: kind + relative rect (0…1) + label.
/// Derived from recorded interaction targets (elementBounds/windowBounds,
/// coordinates, action) — mirrors prototype `haloFor()` + `autoHalo`.
public struct FlowlineHalo: Equatable {
    public var kind: FlowlineHaloKind
    /// Relative rect inside the preview frame.
    public var x: Double; public var y: Double; public var w: Double; public var h: Double
    public var label: String
    /// Owning step id — keeps appear-animation + dedup keys unique when two
    /// steps share the same title (duplicate titles must still retrigger).
    public var stepID: String? = nil
    /// Short label safe to render inside a tiny halo rect (tail-truncated).
    public var shortLabel: String {
        guard label.count > 40 else { return label }
        return String(label.prefix(40)) + "…"
    }
    /// Unique animation/identity key: step + kind + position.
    public var triggerKey: String {
        let sx = String(format: "%.3f", x), sy = String(format: "%.3f", y)
        return "\(stepID ?? label)-\(kind.rawValue)-\(sx)-\(sy)"
    }
}

public enum FlowlineHaloResolver {
    /// Clamp a relative rect so it stays fully inside 0…1 (containment, not
    /// just independent clamping — guarantees x+w<=1 and y+h<=1).
    public static func clampedRect(x: Double, y: Double, w: Double, h: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        let cw = max(0.04, min(0.6, w))
        let ch = max(0.04, min(0.6, h))
        let cx = max(0, min(1 - cw, x))
        let cy = max(0, min(1 - ch, y))
        return (cx, cy, cw, ch)
    }

    /// Stable djb2 hash (Swift's `hashValue` is per-process seeded, so it
    /// can't be used for deterministic layout).
    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 { h = h &* 33 &+ UInt64(b) }
        return h
    }

    /// Deterministic per-step offset in [-radius, +radius] so identical
    /// fallbacks never pile pixel-perfectly.
    private static func jitter(for id: String, radius: Double) -> (dx: Double, dy: Double) {
        let h = stableHash(id)
        let dx = (Double((h >> 16) % 1000) / 1000.0 - 0.5) * 2 * radius
        let dy = (Double(h % 1000) / 1000.0 - 0.5) * 2 * radius
        return (dx, dy)
    }

    public static func halo(for step: Step) -> FlowlineHalo? {
        let label = step.actionDescription.isEmpty ? step.appName : step.actionDescription
        let kind = kind(for: step)
        // Prefer the recorded element rect when available.
        if let eb = step.elementBounds, let wb = step.windowBounds, wb.width > 0, wb.height > 0 {
            let x = (eb.x - wb.x) / wb.width
            let y = (eb.y - wb.y) / wb.height
            let r = clampedRect(x: x, y: y, w: eb.width / wb.width, h: eb.height / wb.height)
            return FlowlineHalo(kind: kind, x: r.x, y: r.y, w: r.w, h: r.h, label: label, stepID: step.id)
        }
        // Coordinates + window rect: place a click-sized marker centered on
        // the true recorded point (plus a tiny per-step nudge so repeated
        // clicks at the same point don't hide each other).
        if let c = step.coordinates, let wb = step.windowBounds, wb.width > 0, wb.height > 0 {
            let px = (c.x - wb.x) / wb.width
            let py = (c.y - wb.y) / wb.height
            let j = jitter(for: step.id, radius: 0.015)
            let r = clampedRect(x: px - 0.06 + j.dx, y: py - 0.04 + j.dy, w: 0.12, h: 0.08)
            return FlowlineHalo(kind: kind, x: r.x, y: r.y, w: r.w, h: r.h, label: label, stepID: step.id)
        }
        if step.coordinates != nil {
            // Coordinates are screen points; without a window rect we can't
            // map them, so scatter deterministically around center-ish.
            let j = jitter(for: step.id, radius: 0.10)
            let r = clampedRect(x: 0.42 + j.dx, y: 0.42 + j.dy, w: 0.12, h: 0.08)
            return FlowlineHalo(kind: kind, x: r.x, y: r.y, w: r.w, h: r.h, label: label, stepID: step.id)
        }
        // Manual steps without geometry get no halo.
        if step.action == .manual { return nil }
        let j = jitter(for: step.id, radius: 0.12)
        let r = clampedRect(x: 0.35 + j.dx, y: 0.35 + j.dy, w: 0.3, h: 0.2)
        return FlowlineHalo(kind: kind, x: r.x, y: r.y, w: r.w, h: r.h, label: label, stepID: step.id)
    }

    public static func kind(for step: Step) -> FlowlineHaloKind {
        switch step.action {
        case .click, .doubleClick, .rightClick: return .click
        case .keyPress: return .key
        case .typing, .writeCode: return .callout
        case .mouseDrag: return .arrow
        case .appSwitch: return .spotlight
        case .manual: return .rect
        }
    }

    public static func verb(for step: Step) -> String {
        switch step.action {
        case .click: return "Click"
        case .rightClick: return "Right-click"
        case .doubleClick: return "Double-click"
        case .keyPress: return step.hotkeyCombo ?? "Press"
        case .typing: return "Type"
        case .writeCode: return "Write"
        case .appSwitch: return "Open"
        case .mouseDrag: return "Drag"
        case .manual: return "Do"
        }
    }

    public static func target(for step: Step) -> String {
        if let t = step.elementTitle, !t.isEmpty { return t }
        if !step.windowTitle.isEmpty { return step.windowTitle }
        if !step.appName.isEmpty { return step.appName }
        return "target"
    }
}

/// Publish state for the header pill + publish menu.
public enum FlowlinePublishState: String {
    case draft, published, updated
    public var pill: String {
        switch self {
        case .draft: return "Draft"
        case .published: return "Published"
        case .updated: return "Unpublished changes"
        }
    }
}

/// Lightweight undo/redo over serialized steps.
public struct FlowlineHistory {
    public private(set) var undo: [Data] = []
    public private(set) var redo: [Data] = []
    public mutating func push(_ steps: [Step]) {
        if let d = try? JSONEncoder().encode(steps) {
            undo.append(d)
            if undo.count > 60 { undo.removeFirst() }
            redo.removeAll()
        }
    }
    public mutating func popUndo(current: [Step]) -> [Step]? {
        guard let d = undo.popLast(),
              let steps = try? JSONDecoder().decode([Step].self, from: d) else { return nil }
        if let c = try? JSONEncoder().encode(current) { redo.append(c) }
        return steps
    }
    public mutating func popRedo(current: [Step]) -> [Step]? {
        guard let d = redo.popLast(),
              let steps = try? JSONDecoder().decode([Step].self, from: d) else { return nil }
        if let c = try? JSONEncoder().encode(current) { undo.append(c) }
        return steps
    }
}
