import SwiftUI
import FlowlineEngine

/// Shortcuts pane — keyboard capture policy + recording toggle.
public struct SettingsShortcutsPane: View {
    @Binding public var settings: FlowlineSettings

    public init(settings: Binding<FlowlineSettings>) {
        self._settings = settings
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Capture modifier shortcuts (⌘S, ⌃C…)", isOn: $settings.hotkeyCapture.captureModifierShortcuts)
                Text("Each shortcut becomes a discrete ‘key_press’ step with a screenshot.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Capture navigation keys (Esc, Tab, arrows)", isOn: $settings.hotkeyCapture.captureNavigationKeys)
            } header: {
                Text("Keyboard Capture")
            }

            Section {
                Text("One combo per line (e.g. ⌘Tab, ⌘Space). These are consumed and never recorded.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: ignoredCombosBinding)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .border(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                Text("System combos like ⌘Tab / ⌘Space are always consumed.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Always Ignored")
            }

            Section {
                LabeledContent("Recording toggle") {
                    TextField("⌥ Space", text: $settings.hotkeys.toggleRecording)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                }
                Text("Default ⌥ Space. The recorder consumes this combo and never records it as a step.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Toggle")
            }
        }
        .formStyle(.grouped)
    }

    private var ignoredCombosBinding: Binding<String> {
        Binding(
            get: { settings.hotkeyCapture.ignoredCombos.sorted().joined(separator: "\n") },
            set: { newValue in
                settings.hotkeyCapture.ignoredCombos = Set(
                    newValue.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                )
            }
        )
    }
}
