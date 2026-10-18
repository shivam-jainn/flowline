import SwiftUI
import FlowlineEngine
import FlowlineIR
import FlowlinePublishing

/// Publishing pane — every persisted `PublishingSettings` knob now has UI,
/// including the two previously dead toggles:
/// `includeTimestamp` and `enableInteractiveChecklists` are now wired
/// through `WebDocGenerator` (see WebDocSections).
public struct SettingsPublishingPane: View {
    @Binding public var settings: FlowlineSettings

    public init(settings: Binding<FlowlineSettings>) {
        self._settings = settings
    }

    public var body: some View {
        Form {
            Section {
                Picker("Default theme", selection: $settings.publishing.defaultTheme) {
                    ForEach(ThemeName.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                LabeledContent("Author") {
                    TextField("Technical writer", text: $settings.publishing.authorName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }
                LabeledContent("Company") {
                    TextField("Flowline Docs", text: $settings.publishing.companyName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                }
            } header: {
                Text("Branding")
            }

            Section {
                Picker("PDF paper size", selection: $settings.publishing.pdfPaperSize) {
                    Text("A4").tag("A4")
                    Text("US Letter").tag("Letter")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("PDF")
            }

            Section {
                Toggle("Interactive checklists", isOn: $settings.publishing.enableInteractiveChecklists)
                Text("Adds per-step checkboxes with progress + localStorage persistence. Off renders static step cards.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show recorded date", isOn: $settings.publishing.includeTimestamp)
                Text("Shows the RECORDED strip in the guide header. Off hides the date for evergreen docs.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Guide Content")
            }

            Section {
                Picker("Keycap style", selection: $settings.publishing.keycapStyle) {
                    ForEach(KeycapStyle.allCases, id: \.self) { k in
                        Text("\(k.label) — \(k.blurb)").tag(k)
                    }
                }
                Text("3D Keys = deep mechanical dish. Mac 3D = Apple bezel gradient. Mac 2D = flat matte.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Mouse style", selection: $settings.publishing.mouseStyle) {
                    ForEach(MouseStyle.allCases, id: \.self) { m in
                        Text("\(m.label) — \(m.blurb)").tag(m)
                    }
                }
                Text("Flat = thin ring. Mac 2D = native pointer badge. Mac 3D = glow + double ring + shadow.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Keystroke Visuals")
            }
        }
        .formStyle(.grouped)
    }
}
