import SwiftUI
import StepItCore

public struct ReviewWindow: View {
    @State public var session: StepSession
    @State private var settings: StepItSettings = SessionStore.shared.loadSettings()
    
    // AI Synthesis state
    @State private var selectedStyle: DocumentationStyle = .sopGuide
    @State private var customInstructions: String = ""
    @State private var isSynthesizing = false
    @State private var synthesizedText: String = ""
    @State private var synthesisError: String?
    
    // Export state
    @State private var exportedWebURL: URL?
    @State private var exportedPDFURL: URL?
    @State private var exportedMarkdownURL: URL?
    @State private var isExporting = false
    @State private var exportStatusMessage: String?
    
    @State private var selectedStepIndex: Int = 1
    
    public init(session: StepSession) {
        _session = State(initialValue: session)
        _synthesizedText = State(initialValue: session.synthesizedMarkdown ?? "")
    }
    
    public var body: some View {
        HSplitView {
            // Left Column: Steps Timeline & Inspector
            stepsListPane
                .frame(minWidth: 420, idealWidth: 480)
            
            // Right Column: AI Synthesis & 1-Click Publishing Pane
            rightActionPane
                .frame(minWidth: 460, idealWidth: 540)
        }
        .frame(minWidth: 980, minHeight: 680)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.accentColor)
                    Text(session.title)
                        .font(.headline)
                    Text("• \(session.steps.count) steps")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Picker("Theme", selection: $session.theme) {
                    ForEach(ThemeName.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
    }
    
    // MARK: - Left Pane: Steps Timeline
    
    private var stepsListPane: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timeline Steps")
                        .font(.headline)
                    Text("Click on a step to view captured assets & edit notes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: addManualStep) {
                    Label("Add Step", systemImage: "plus")
                }
                .controlSize(.small)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Step Cards List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(session.steps.indices, id: \.self) { idx in
                        stepCard(index: idx)
                    }
                }
                .padding(14)
            }
        }
    }
    
    private func stepCard(index: Int) -> some View {
        let step = session.steps[index]
        let isSelected = selectedStepIndex == step.index
        
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                // Step Number Badge
                Text("\(step.index)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor))
                
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Step Description", text: $session.steps[index].actionDescription)
                        .font(.system(size: 13, weight: .semibold))
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    HStack(spacing: 8) {
                        if !step.appName.isEmpty {
                            Label(step.appName, systemImage: "app.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        if let role = step.elementRole {
                            Text(role)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                // Delete button
                Button(action: {
                    deleteStep(at: index)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Thumbnail / Scrubber
            if let screenshotPath = step.assets.screenshot {
                let imgURL = SessionStore.shared.resolveMediaPath(sessionID: session.id, relativePath: screenshotPath)
                if let nsImage = NSImage(contentsOf: imgURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 180)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            
            // User notes input
            TextField("Optional guidance or note for this step...", text: Binding(
                get: { session.steps[index].userNotes ?? "" },
                set: { session.steps[index].userNotes = $0 }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.system(size: 11))
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.06) : Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            selectedStepIndex = step.index
        }
    }
    
    // MARK: - Right Pane: AI Synthesis & 1-Click Publishing
    
    private var rightActionPane: some View {
        VStack(spacing: 0) {
            // Tab Selector
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: AI Synthesis Card
                    aiSynthesisSection
                    
                    Divider()
                    
                    // Section 2: 1-Click Publishing Card
                    publishingSection
                }
                .padding(16)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private var aiSynthesisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Synthesis Gateway", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Spacer()
                Text(settings.gateway.provider.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Picker("Template Style", selection: $selectedStyle) {
                ForEach(DocumentationStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            TextField("Custom Instructions (e.g. 'Use concise bullet points', 'Target macOS Sequoia')", text: $customInstructions)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12))
            
            HStack {
                Button(action: startAISynthesis) {
                    HStack(spacing: 6) {
                        if isSynthesizing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Synthesizing Stream...")
                        } else {
                            Image(systemName: "bolt.badge.automatic.fill")
                            Text("Generate Documentation with AI")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(isSynthesizing || session.steps.isEmpty)
            }
            
            if let err = synthesisError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Output Markdown Preview
            if !synthesizedText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Synthesized Output")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(synthesizedText, forType: .string)
                        }) {
                            Label("Copy Markdown", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                    }
                    
                    TextEditor(text: $synthesizedText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 200)
                        .border(Color.secondary.opacity(0.2), width: 1)
                        .cornerRadius(6)
                }
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
    
    private var publishingSection: some View {
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
                            PublishingCoordinator.shared.openInBrowser(url: webURL)
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
                            PublishingCoordinator.shared.openInBrowser(url: pdfURL)
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
                            PublishingCoordinator.shared.revealInFinder(url: mdURL)
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
    
    // MARK: - Actions
    
    private func addManualStep() {
        let newIdx = session.steps.count + 1
        let step = Step(
            index: newIdx,
            timestamp: Date(),
            action: .manual,
            appName: "Manual Step",
            actionDescription: "Enter step instructions"
        )
        session.steps.append(step)
        try? SessionStore.shared.saveSession(session)
    }
    
    private func deleteStep(at index: Int) {
        session.steps.remove(at: index)
        for i in session.steps.indices {
            session.steps[i].index = i + 1
        }
        try? SessionStore.shared.saveSession(session)
    }
    
    private func startAISynthesis() {
        isSynthesizing = true
        synthesisError = nil
        synthesizedText = ""
        
        Task {
            do {
                let stream = AIGatewayClient.shared.generateStream(
                    session: session,
                    settings: settings.gateway,
                    style: selectedStyle,
                    customInstructions: customInstructions
                )
                
                for try await token in stream {
                    await MainActor.run {
                        self.synthesizedText += token
                    }
                }
                
                await MainActor.run {
                    self.session.synthesizedMarkdown = self.synthesizedText
                    try? SessionStore.shared.saveSession(self.session)
                    self.isSynthesizing = false
                }
            } catch {
                await MainActor.run {
                    self.synthesisError = error.localizedDescription
                    self.isSynthesizing = false
                }
            }
        }
    }
    
    private func exportWebDoc() {
        do {
            let url = try PublishingCoordinator.shared.exportWeb(session: session, settings: settings)
            self.exportedWebURL = url
            self.exportStatusMessage = "Web Documentation exported to \(url.lastPathComponent)!"
        } catch {
            self.exportStatusMessage = "Export failed: \(error.localizedDescription)"
        }
    }
    
    private func exportPDFDoc() {
        Task {
            do {
                let url = try await PublishingCoordinator.shared.exportPDF(session: session, settings: settings)
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
            let url = try PublishingCoordinator.shared.exportMarkdown(session: session)
            self.exportedMarkdownURL = url
            self.exportStatusMessage = "README.md exported successfully!"
        } catch {
            self.exportStatusMessage = "Markdown export failed: \(error.localizedDescription)"
        }
    }
}
