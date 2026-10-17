import SwiftUI
import StepItIR
import StepItPublishing

/// 1-click publishing pane of the review window (R/M1-07 split).
/// Drives web/PDF/markdown exports through the injected publishing service.
public struct ReviewExportPane: View {
    public var session: StepSession
    public var publishing: PublishingSettings
    public var publisher: any ReviewPublishingService

    @State private var exportedWebURL: URL?
    @State private var exportedPDFURL: URL?
    @State private var exportedMarkdownURL: URL?
    @State private var exportStatusMessage: String?

    public init(
        session: StepSession,
        publishing: PublishingSettings,
        publisher: any ReviewPublishingService
    ) {
        self.session = session
        self.publishing = publishing
        self.publisher = publisher
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("1-Click Multi-Format Publishing", systemImage: "paperplane.fill")
                .font(.headline)

            Text("Export this workflow session as an interactive website, print-ready PDF, or markdown README.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                // Export Web Doc
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("🌐 Interactive Web Documentation")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Self-contained HTML site with stepper, checklist mode & media toggles.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let webURL = exportedWebURL {
                        Button("Open") {
                            publisher.openInBrowser(url: webURL)
                        }
                        .controlSize(.small)
                    }
                    Button("Export Web") {
                        exportWebDoc()
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Export PDF
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("📄 Print-Ready Styled PDF")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Executive SOP with running headers, page breaks & callouts.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let pdfURL = exportedPDFURL {
                        Button("Open") {
                            publisher.openInBrowser(url: pdfURL)
                        }
                        .controlSize(.small)
                    }
                    Button("Export PDF") {
                        exportPDFDoc()
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Export Markdown
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("📝 Markdown & Media Assets")
                            .font(.system(size: 13, weight: .semibold))
                        Text("GitHub README with step links and PNG/GIF embeds.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let mdURL = exportedMarkdownURL {
                        Button("Reveal") {
                            publisher.revealInFinder(url: mdURL)
                        }
                        .controlSize(.small)
                    }
                    Button("Export MD") {
                        exportMarkdownDoc()
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            if let msg = exportStatusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func exportWebDoc() {
        do {
            let url = try publisher.exportWeb(session: session, publishing: publishing)
            self.exportedWebURL = url
            self.exportStatusMessage = "Web Documentation exported to \(url.lastPathComponent)!"
        } catch {
            self.exportStatusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportPDFDoc() {
        Task {
            do {
                let url = try await publisher.exportPDF(session: session, publishing: publishing)
                await MainActor.run {
                    self.exportedPDFURL = url
                    self.exportStatusMessage = "PDF Guide exported successfully!"
                }
            } catch {
                await MainActor.run {
                    self.exportStatusMessage = "PDF generation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func exportMarkdownDoc() {
        do {
            let url = try publisher.exportMarkdown(session: session)
            self.exportedMarkdownURL = url
            self.exportStatusMessage = "README.md exported successfully!"
        } catch {
            self.exportStatusMessage = "Markdown export failed: \(error.localizedDescription)"
        }
    }
}
