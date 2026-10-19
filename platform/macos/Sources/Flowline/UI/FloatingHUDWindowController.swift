import AppKit
import QuartzCore
import FlowlineFixtures
import FlowlineStorage
import FlowlineMacCapture
import FlowlineCaptureAPI
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePipeline
import FlowlineEngine
import FlowlineIR
import SwiftUI

/// Hosts the agent island (`AgentIslandHUDView`) as the floating capture HUD.
///
/// UI1.md rule 5: the island kills the generic recording pill — this
/// controller now shows the island, full stop. Window contract is unchanged:
/// top-center floating panel, `sharingType = .none` so the HUD never
/// photobombs captures (see `RecordingScreenVisibilityTests`), joins all
/// spaces, draggable by its background. The panel height tracks the island:
/// compact while collapsed, taller while expanded, always top-anchored.
public final class FloatingHUDWindowController: @unchecked Sendable {
    private let controller: WorkflowController

    private var window: NSPanel?
    private var hostingView: NSHostingView<AgentIslandHUDView>?
    public var onStopRequested: (() -> Void)?

    private static let panelWidth: CGFloat = 380
    private static let minHeight: CGFloat = 80
    private static let maxHeight: CGFloat = 320
    private static let topMargin: CGFloat = 24

    public init(controller: WorkflowController) {
        self.controller = controller
    }

    @MainActor
    public func show() {
        if window == nil {
            createWindow()
        }

        fitPanelToContent(animated: false)
        positionWindow()
        window?.orderFrontRegardless()
    }

    @MainActor
    public func hide() {
        window?.orderOut(nil)
    }

    @MainActor
    private func createWindow() {
        let hudView = AgentIslandHUDView(controller: controller) { [weak self] in
            self?.onStopRequested?()
        } onExpandedChange: { [weak self] _ in
            Task { @MainActor in
                self?.fitPanelToContent(animated: true)
            }
        }

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView = hostingView

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 116),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView

        self.window = panel
    }

    /// Resize the panel to the island's intrinsic height, keeping the top
    /// edge pinned so expansion grows downward from under the menu bar.
    ///
    /// Smoothness contract: layout is forced before measuring (otherwise the
    /// target height is a frame stale and the panel visibly corrects
    /// mid-flight), and the frame animates with the EXACT curve + duration
    /// the island content uses (`FlowMotion.standardSlow`: cubic-bezier
    /// 0.28/0/0.22/1 over 0.32s). The old `setFrame(animate:)` ran AppKit's
    /// default timing against SwiftUI's custom curve — that desync was the
    /// visible judder on every expand/collapse.
    @MainActor
    private func fitPanelToContent(animated: Bool) {
        guard let window, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let target = hostingView.fittingSize.height
        guard target > 0 else { return }
        let height = min(max(target, Self.minHeight), Self.maxHeight)
        var frame = window.frame
        let delta = height - frame.size.height
        guard abs(delta) > 0.5 else { return }
        frame.size.width = Self.panelWidth
        frame.size.height = height
        frame.origin.y -= delta
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = FlowMotion.slow
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.28, 0, 0.22, 1)
                ctx.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    @MainActor
    private func positionWindow() {
        guard let window = window else { return }
        // Show on the display the user is working on, not always main.
        let screen = ScreenResolver.screenForMouse() ?? NSScreen.main
        guard let screen else { return }
        let screenRect = screen.visibleFrame
        let size = window.frame.size

        let x = screenRect.origin.x + (screenRect.width - size.width) / 2.0
        let y = screenRect.origin.y + screenRect.height - size.height - Self.topMargin

        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
