import SwiftUI
import StepItEngine
import StepItIR
import StepItPipeline

/// Capture pane of Settings (R/M1-07 split).
/// Edits the media-capture section through a binding.
public struct SettingsCapturePane: View {
    @Binding public var settings: StepItSettings

    public init(settings: Binding<StepItSettings>) {
        self._settings = settings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(label: Label("Media Capture Engine", systemImage: "camera.fill")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Capture Mode", selection: $settings.capture.mediaMode) {
                            ForEach(MediaMode.allCases, id: \.self) { (m: MediaMode) in
                                Text(m.displayName).tag(m)
                            }
                        }

                        Stepper("Animated GIF Frame Rate: \(settings.capture.gifFps) fps", value: $settings.capture.gifFps, in: 10...30)

                        Toggle("Highlight Clicks with Indicator Marker", isOn: $settings.capture.highlightClicks)

                        Slider(value: $settings.capture.highlightRadius, in: 16...48, step: 2) {
                            Text("Highlight Marker Radius: \(Int(settings.capture.highlightRadius)) pt")
                        }

                        Toggle("Record App Switches (Switch to Slack, …)", isOn: $settings.capture.recordAppSwitches)
                            .help("Emits an 'app_switch' step whenever the frontmost application changes during a recording.")
                    }
                    .padding(10)
                }
            }
            .padding()
        }
    }
}
