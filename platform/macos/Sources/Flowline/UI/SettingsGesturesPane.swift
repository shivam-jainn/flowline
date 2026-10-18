import SwiftUI
import FlowlineEngine
import FlowlineIR
import FlowlineCaptureAPI
import FlowlineFixtures

/// Smart gestures pane — extracted from SettingsView, kept feature-complete
/// (shake, hot corners, click & hold, live playground) but in Form style.
public struct SettingsGesturesPane: View {
    @Binding public var settings: FlowlineSettings
    var controller: WorkflowController

    @State private var liveTestFeedback: String?
    @State private var liveTestFeedbackAction: GestureAction?

    public init(settings: Binding<FlowlineSettings>, controller: WorkflowController) {
        self._settings = settings
        self.controller = controller
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Enable shake detection", isOn: $settings.gestures.shakeToPauseEnabled)
                if settings.gestures.shakeToPauseEnabled {
                    Picker("Trigger action", selection: $settings.gestures.shakeAction) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Sensitivity", selection: $settings.gestures.shakeSensitivity) {
                        ForEach(GestureSensitivity.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Shake the pointer horizontally to trigger instantly — no hotkey needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Shake to Action")
            }

            Section {
                Toggle("Enable hot corners", isOn: $settings.gestures.hotCorners.enabled)
                if settings.gestures.hotCorners.enabled {
                    Picker("Top-left", selection: $settings.gestures.hotCorners.topLeft) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Top-right", selection: $settings.gestures.hotCorners.topRight) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Bottom-left", selection: $settings.gestures.hotCorners.bottomLeft) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Bottom-right", selection: $settings.gestures.hotCorners.bottomRight) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Slam the cursor into a corner and dwell 0.2s to trigger.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Hot Corners")
            }

            Section {
                Picker("Middle-click", selection: $settings.gestures.middleClickAction) {
                    ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Double right-click", selection: $settings.gestures.doubleRightClickAction) {
                    ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Long press", selection: $settings.gestures.longPressAction) {
                    ForEach(GestureAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.gestures.longPressAction != .none {
                    LabeledContent("Hold duration") {
                        HStack {
                            Slider(value: $settings.gestures.longPressDurationSec, in: 0.5...1.5, step: 0.1)
                                .frame(maxWidth: 160)
                            Text(String(format: "%.1fs", settings.gestures.longPressDurationSec))
                                .monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Click & Hold")
            }

            Section {
                if let feedback = liveTestFeedback, let action = liveTestFeedbackAction {
                    Label("Detected: \(feedback) → \(action.title)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Label("Perform a gesture to test sensitivity.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Simulate shake") {
                        liveTestFeedback = "Mouse shake (simulated)"
                        liveTestFeedbackAction = settings.gestures.shakeAction
                    }.font(.caption)
                    Button("Simulate corner") {
                        liveTestFeedback = "Top-right corner (simulated)"
                        liveTestFeedbackAction = settings.gestures.hotCorners.topRight
                    }.font(.caption)
                }
            } header: {
                Text("Test Playground")
            }
        }
        .formStyle(.grouped)
        .onAppear { Task { await controller.applyGestureSettings(settings.gestures) } }
        .onChange(of: controller.lastGestureEvent) { _, event in
            guard let event else { return }
            liveTestFeedback = event.name
            liveTestFeedbackAction = event.action
        }
    }
}
