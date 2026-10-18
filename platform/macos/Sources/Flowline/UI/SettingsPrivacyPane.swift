import SwiftUI
import FlowlineEngine
import FlowlinePipeline

/// Privacy pane — Form layout consistent with gateway/capture.
/// All controls run 100% on-device (Apple Vision OCR); nothing uploads.
public struct SettingsPrivacyPane: View {
    @Binding public var settings: FlowlineSettings

    public init(settings: Binding<FlowlineSettings>) {
        self._settings = settings
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Mask passwords", isOn: $settings.privacy.maskSecureInputFields)
                Text("Keystrokes in secure fields become ••••. Raw characters never leave the field, and snapshots are blacked out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Passwords & Secure Input")
            }

            Section {
                Toggle("Blur sensitive text in screenshots", isOn: $settings.privacy.enableOfflineOCRRedaction)
                    .fontWeight(.medium)
                if settings.privacy.enableOfflineOCRRedaction {
                    Toggle("API keys & tokens", isOn: $settings.privacy.autoRedactAPIKeys)
                        .help("OpenAI sk-…, AWS AKIA…, GitHub ghp_…, JWTs, Bearer tokens")
                    Toggle("Credit cards", isOn: $settings.privacy.autoRedactCreditCards)
                    Toggle("Email addresses", isOn: $settings.privacy.autoRedactEmails)

                    Picker("Style", selection: $settings.privacy.blurStyle) {
                        ForEach(RedactionBlurStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    LabeledContent("Blur radius") {
                        HStack {
                            Slider(value: $settings.privacy.blurRadius, in: 4...40, step: 2)
                                .frame(maxWidth: 200)
                                .disabled(settings.privacy.blurStyle == .blackout)
                            Text("\(Int(settings.privacy.blurRadius)) pt")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom patterns (one regex per line)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: customPatternsBinding)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 60)
                            .border(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                    .padding(.top, 4)

                    Text("Blurred steps show a shield badge in Review and can be toggled with the preserved original before publishing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Apple Vision OCR runs fully on-device — nothing is uploaded when enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Offline Redaction")
            }
        }
        .formStyle(.grouped)
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
