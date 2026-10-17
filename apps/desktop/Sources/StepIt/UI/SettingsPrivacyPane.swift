import SwiftUI
import StepItEngine
import StepItPipeline

/// Privacy pane of Settings (R/M1-07 split).
/// Edits the Phase-2 privacy section through a binding.
public struct SettingsPrivacyPane: View {
    @Binding public var settings: StepItSettings

    public init(settings: Binding<StepItSettings>) {
        self._settings = settings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(label: Label("Password & Secure Input", systemImage: "key.fill")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Mask Password Fields", isOn: $settings.privacy.maskSecureInputFields)
                            .help("Keystrokes in secure fields are stored as •••• or dropped entirely — raw characters never leave the field.")
                        Text("Secure-field snapshots are blacked out before they are saved, and values are stripped from the step model.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                }

                GroupBox(label: Label("Offline OCR Redaction", systemImage: "eye.slash.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Blur Sensitive Text in Screenshots", isOn: $settings.privacy.enableOfflineOCRRedaction)
                            .fontWeight(.medium)
                            .help("Apple Vision OCR runs fully on-device — nothing is uploaded.")

                        if settings.privacy.enableOfflineOCRRedaction {
                            Toggle("Auto-Redact API Keys & Tokens", isOn: $settings.privacy.autoRedactAPIKeys)
                            Toggle("Auto-Redact Credit Cards", isOn: $settings.privacy.autoRedactCreditCards)
                            Toggle("Auto-Redact Email Addresses", isOn: $settings.privacy.autoRedactEmails)

                            Picker("Redaction Style", selection: $settings.privacy.blurStyle) {
                                ForEach(RedactionBlurStyle.allCases, id: \.self) { (style: RedactionBlurStyle) in
                                    Text(style.displayName).tag(style)
                                }
                            }

                            Slider(value: $settings.privacy.blurRadius, in: 4...40, step: 2) {
                                Text("Blur Radius: \(Int(settings.privacy.blurRadius)) pt")
                            }
                            .disabled(settings.privacy.blurStyle == .blackout)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Custom Regex Patterns (one per line)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextEditor(text: customPatternsBinding)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(height: 60)
                                    .border(Color.secondary.opacity(0.2))
                                    .cornerRadius(4)
                            }

                            Text("Blurred steps show a 🛡️ badge in the Review Window and can be toggled (with the preserved original) before publishing.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(10)
                }
            }
            .padding()
        }
    }

    private var customPatternsBinding: Binding<String> {
        Binding(
            get: { settings.privacy.customRegexPatterns.joined(separator: "\n") },
            set: { newValue in
                settings.privacy.customRegexPatterns = newValue
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}
