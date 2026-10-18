import Foundation
import FlowlineIR

// MARK: - Shortcut Capture Configuration (owns: FlowlinePipeline)
// Moved from FlowlineCore/Model/Settings.swift during R/M1-03: the engine and
// `HotkeyRecognizer` policy consume it, so it must live pipeline-adjacent.
// FlowlineCore re-exports via typealias until R/M1-07.

/// Which keyboard chords become discrete documentation steps.
public struct HotkeyCaptureSettings: Codable, Sendable, Equatable {
    /// Record `⌘`/`⌃` chords (`⌘S`, `⌘⇧P`, `⌃A`, …) as `.keyPress` steps.
    public var captureModifierShortcuts: Bool = true
    /// Record navigation keys (Esc, Tab, arrows, F-keys) as `.keyPress` steps.
    public var captureNavigationKeys: Bool = true
    /// Extra chords the recorder must consume and never record (app-registered
    /// shortcuts). System combos like `⌘Tab` / `⌘Space` are always consumed.
    public var ignoredCombos: Set<String> = []

    public init() {}
}
