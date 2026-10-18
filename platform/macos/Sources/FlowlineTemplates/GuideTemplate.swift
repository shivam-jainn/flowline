import Foundation
import FlowlineIR

/// One guide-mode template in the plugin-based template catalogue.
///
/// Data mirror of `templates/<id>/manifest.json` (validated by
/// `shared/contracts/template.schema.json`). `theme` is a
/// `FlowlineIR.ThemeName` raw value and `synthesisStyle` a
/// `FlowlineAIGateway.DocumentationStyle` raw value, kept as plain strings so
/// this target stays Foundation-only (FlowlineIR + Foundation imports only).
public struct GuideTemplate: Sendable, Equatable, Hashable {
    public var id: String
    public var label: String
    public var copy: String
    public var theme: String
    public var synthesisStyle: String
    public var quirks: [String]
    public var supportsChecklist: Bool
    public var showsCode: Bool
    public var showsTargetLine: Bool
    public var largeTitles: Bool

    public init(
        id: String,
        label: String,
        copy: String,
        theme: String,
        synthesisStyle: String,
        quirks: [String] = [],
        supportsChecklist: Bool = false,
        showsCode: Bool = false,
        showsTargetLine: Bool = false,
        largeTitles: Bool = false
    ) {
        self.id = id
        self.label = label
        self.copy = copy
        self.theme = theme
        self.synthesisStyle = synthesisStyle
        self.quirks = quirks
        self.supportsChecklist = supportsChecklist
        self.showsCode = showsCode
        self.showsTargetLine = showsTargetLine
        self.largeTitles = largeTitles
    }

    /// The 7 built-in guide modes. Labels, copy, themes and synthesis styles
    /// mirror `FlowlineGuideMode` (track 2 owns the UI; this is the data).
    public static var all: [GuideTemplate] {
        [
            GuideTemplate(
                id: "standard",
                label: "Standard guide",
                copy: "Visual and explanation for every Step.",
                theme: "modern-minimal",
                synthesisStyle: "sop_guide"
            ),
            GuideTemplate(
                id: "checklist",
                label: "Checklist",
                copy: "A tickable list of everything to do.",
                theme: "modern-minimal",
                synthesisStyle: "sop_guide",
                quirks: ["checklist-markers"],
                supportsChecklist: true
            ),
            GuideTemplate(
                id: "sop",
                label: "SOP",
                copy: "Action-oriented structured instructions.",
                theme: "enterprise-sop",
                synthesisStyle: "sop_guide",
                quirks: ["numbered-steps"]
            ),
            GuideTemplate(
                id: "tutorial",
                label: "Tutorial",
                copy: "More explanatory, written for a first run.",
                theme: "modern-minimal",
                synthesisStyle: "sop_guide",
                quirks: ["guidance-notes"]
            ),
            GuideTemplate(
                id: "runbook",
                label: "Runbook",
                copy: "Step, command, expected result, verification.",
                theme: "enterprise-sop",
                synthesisStyle: "bug_report",
                quirks: ["code-fence"],
                showsCode: true
            ),
            GuideTemplate(
                id: "presentation",
                label: "Presentation",
                copy: "Large visuals with minimal text.",
                theme: "developer-dark",
                synthesisStyle: "executive_summary",
                quirks: ["uppercase-titles"],
                largeTitles: true
            ),
            GuideTemplate(
                id: "reference",
                label: "Reference",
                copy: "Compact, searchable summary.",
                theme: "modern-minimal",
                synthesisStyle: "automation_script",
                quirks: ["target-line"],
                showsTargetLine: true
            ),
        ]
    }

    /// Look up a built-in template by mode id. Returns nil for unknown ids
    /// so callers can fall back to standard rendering.
    public static func make(id: String) -> GuideTemplate? {
        all.first { $0.id == id }
    }
}
