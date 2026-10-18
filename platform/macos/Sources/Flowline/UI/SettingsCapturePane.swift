import SwiftUI
import FlowlineEngine
import FlowlineIR

/// Capture pane — exposes every persisted `CaptureSettings` knob.
///
/// Previously `highlightColorHex` and pre/post clip durations were persisted
/// but had no UI. Now: segmented mode, FPS stepper, pre/post sliders,
/// highlight color picker + radius, app-switch toggle.
public struct SettingsCapturePane: View {
    @Binding public var settings: FlowlineSettings

    public init(settings: Binding<FlowlineSettings>) {
        self._settings = settings
    }

    public var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $settings.capture.mediaMode) {
                    ForEach(MediaMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(modeBlurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Media Mode")
            }

            Section {
                LabeledContent("Frame rate") {
                    HStack {
                        Stepper("\(settings.capture.gifFps) fps", value: $settings.capture.gifFps, in: 10...30)
                    }
                }
                LabeledContent("Lead-in") {
                    HStack {
                        Slider(value: $settings.capture.clipDurationPreClickSec, in: 0.1...2.0, step: 0.1)
                            .frame(maxWidth: 200)
                        Text(String(format: "%.1fs", settings.capture.clipDurationPreClickSec))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Trail-out") {
                    HStack {
                        Slider(value: $settings.capture.clipDurationPostClickSec, in: 0.2...3.0, step: 0.1)
                            .frame(maxWidth: 200)
                        Text(String(format: "%.1fs", settings.capture.clipDurationPostClickSec))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Animation Clips")
            } footer: {
                Text("Lead-in / trail-out control how much motion is kept around each click.")
            }

            Section {
                Toggle("Highlight clicks", isOn: $settings.capture.highlightClicks)
                if settings.capture.highlightClicks {
                    LabeledContent("Marker color") {
                        HStack {
                            ColorPicker("", selection: highlightColorBinding)
                                .labelsHidden()
                            Text(settings.capture.highlightColorHex.uppercased())
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Marker size") {
                        HStack {
                            Slider(value: $settings.capture.highlightRadius, in: 16...48, step: 2)
                                .frame(maxWidth: 200)
                            Text("\(Int(settings.capture.highlightRadius)) pt")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Click Indicators")
            }

            Section {
                Toggle("Record app switches", isOn: $settings.capture.recordAppSwitches)
                Text("Emits an ‘app_switch’ step when the frontmost app changes (e.g. Switch to Slack). Off by default to keep guides focused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Steps")
            }
        }
        .formStyle(.grouped)
    }

    private var modeBlurb: String {
        switch settings.capture.mediaMode {
        case .hybrid: return "Screenshots + GIFs — best for most guides."
        case .staticOnly: return "Screenshots only — smallest files, fastest export."
        case .animatedOnly: return "GIFs only — shows motion, larger files."
        }
    }

    private var highlightColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.capture.highlightColorHex) ?? Color.red },
            set: { settings.capture.highlightColorHex = $0.toHex() ?? "#EF4444" }
        )
    }
}

// MARK: - Hex ↔ Color

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0
        )
    }

    func toHex() -> String? {
#if os(macOS)
        let cg = NSColor(self).cgColor
        guard let comps = cg.components, comps.count >= 3 else { return nil }
        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps[1] * 255).rounded())
        let b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
#else
        return nil
#endif
    }
}
