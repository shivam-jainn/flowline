import SwiftUI
import FlowlineFixtures
import FlowlineStorage
import FlowlineMacCapture
import FlowlineCaptureAPI
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePipeline
import FlowlineEngine
import FlowlineIR

/// Controller-bound agent island: maps `WorkflowController` live state onto
/// `AgentIslandView`. This is the capture HUD — it replaces the generic
/// recording pill (`FloatingHUDView`, removed per UI1.md rule 5).
///
/// Narration mapping (proto two-line hierarchy):
/// - finished line: last committed step's `actionDescription`.
/// - current line: the transient gesture notice while visible; otherwise
///   `Watching <app>` while recording, the last step while paused, and a
///   listening placeholder before the first step lands.
/// - app icon + action badge: taken from the last committed step.
public struct AgentIslandHUDView: View {
    @ObservedObject var controller: WorkflowController
    public var onStop: () -> Void
    public var onExpandedChange: (Bool) -> Void

    public init(
        controller: WorkflowController,
        onStop: @escaping () -> Void = {},
        onExpandedChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.controller = controller
        self.onStop = onStop
        self.onExpandedChange = onExpandedChange
    }

    public var body: some View {
        let steps = controller.currentSession?.steps ?? []
        let last = steps.last
        AgentIslandView(
            finishedStep: last?.actionDescription,
            currentStep: currentStep(steps: steps),
            working: controller.state == .recording,
            elapsed: controller.recordingDuration,
            stepCount: controller.stepCount,
            appName: last?.appName.isEmpty == false ? last?.appName : nil,
            appBundleID: last?.bundleIdentifier,
            action: last?.action ?? .click,
            onPauseResume: togglePauseResume,
            onCaptureStep: captureStep,
            onStop: onStop,
            onExpandedChange: onExpandedChange
        )
    }

    private func currentStep(steps: [Step]) -> String {
        if let notice = controller.lastGestureNotice, !notice.isEmpty {
            return notice
        }
        guard let last = steps.last else {
            return controller.state == .recording ? "Listening for activity" : "Paused"
        }
        if controller.state == .recording {
            return last.appName.isEmpty ? "Watching for the next step" : "Watching \(last.appName)"
        }
        return last.actionDescription.isEmpty ? "Paused" : last.actionDescription
    }

    private func togglePauseResume() {
        Task { @MainActor in
            if controller.state == .recording {
                await controller.pauseRecording()
            } else if controller.state == .paused {
                await controller.resumeRecording()
            }
        }
    }

    private func captureStep() {
        Task { @MainActor in
            await controller.captureInstantSnapshot()
        }
    }
}
