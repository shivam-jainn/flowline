import Foundation
import FlowlineIR
import FlowlinePipeline

// MARK: - Terminal Context SPI (Phase 2, T4)
//
// Resolves the working directory (`pwd`) of the terminal the user is typing
// into. Lives in the driver layer as a protocol seam so headless tests inject
// deterministic title/script fixtures and the future Windows/Web drivers can
// implement the same contract.

/// Platform-neutral terminal introspection boundary.
///
/// `Int32` is used instead of Darwin's `pid_t` so the SPI stays portable.
public protocol TerminalInspectorProtocol: Sendable {
    /// Best-effort working directory for the terminal app described by the
    /// inputs. Returns `nil` when the directory cannot be resolved.
    ///
    /// - Parameters:
    ///   - bundleId: Terminal bundle identifier (`com.apple.Terminal`, …).
    ///   - pid: Terminal process id when known.
    ///   - windowTitle: Already-inspected window/tab title (Tier 1 input).
    func inspectCurrentDirectory(forApp bundleId: String?, pid: Int32?, windowTitle: String?) async -> String?
}

extension TerminalInspectorProtocol {
    /// Convenience default so call sites only pass what they have.
    public func inspectCurrentDirectory(forApp bundleId: String?, pid: Int32? = nil, windowTitle: String? = nil) async -> String? {
        await inspectCurrentDirectory(forApp: bundleId, pid: pid, windowTitle: windowTitle)
    }
}

/// Optional driver facet (mirrors `GestureSettingsSink`): drivers that own a
/// `TerminalInspectorProtocol` expose it through this so the engine can enrich
/// terminal steps with `pwd` without knowing the concrete driver.
public protocol TerminalContextProviding: AnyObject, Sendable {
    func inspectTerminalWorkingDirectory(bundleId: String?, pid: Int32?, windowTitle: String?) async -> String?
}
