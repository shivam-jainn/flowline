import SwiftUI
import StepItIR
import StepItStorage

/// Steps timeline + inspector pane of the review window (R/M1-07 split).
/// Mutates the session through a binding; persistence goes through the
/// injected store and Settings opens through the injected callback.
public struct ReviewStepsPane: View {
    @Binding public var session: StepSession
    public var store: SessionStore
    public var onOpenSettings: () -> Void

    @State private var selectedStepIndex: Int = 1
    @State private var showingZoomCrop: [Int: Bool] = [:]

    public init(
        session: Binding<StepSession>,
        store: SessionStore,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self._session = session
        self.store = store
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
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
                HStack(spacing: 8) {
                    Button(action: addManualStep) {
                        Label("Add Step", systemImage: "plus")
                    }
                    .controlSize(.small)

                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                    }
                    .controlSize(.small)
                    .help("Settings")
                }
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
                        if let combo = step.hotkeyCombo {
                            Label(combo, systemImage: "command")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(4)
                        }
                        if let directory = step.workingDirectory {
                            Label(directory, systemImage: "folder")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        redactionBadge(index: index)
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

            // Thumbnail / Scrubber / 2.4x Zoom View
            if let screenshotPath = step.assets.screenshot {
                let showZoom = (showingZoomCrop[step.index] ?? false) && (step.assets.zoomCrop != nil)
                let activePath = showZoom ? (step.assets.zoomCrop ?? screenshotPath) : screenshotPath
                let imgURL = store.resolveMediaPath(sessionID: session.id, relativePath: activePath)

                VStack(alignment: .leading, spacing: 6) {
                    if step.assets.zoomCrop != nil {
                        HStack(spacing: 6) {
                            Button(action: {
                                showingZoomCrop[step.index] = false
                            }) {
                                Text("Overview")
                                    .font(.system(size: 10, weight: !showZoom ? .bold : .regular))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(!showZoom ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(4)

                            Button(action: {
                                showingZoomCrop[step.index] = true
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus.magnifyingglass")
                                    Text("2.4× Zoom")
                                }
                                .font(.system(size: 10, weight: showZoom ? .bold : .regular))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(showZoom ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(4)

                            Spacer()

                            if showZoom {
                                Text("Live DOM Focus Crop")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

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
            }

            // Captured Text / Code Blob / Terminal Command
            if let text = step.textBlob, !text.isEmpty {
                let isTerminal = step.appName.lowercased().contains("terminal") || step.codeLanguage == "bash" || step.codeLanguage == "zsh" || step.codeLanguage == "shell"
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(isTerminal ? "Terminal CLI Command" : (step.isCode ? "Code Snippet (\(step.codeLanguage ?? "code"))" : "Typed Text"), systemImage: isTerminal ? "terminal.fill" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }) {
                            Label(isTerminal ? "Copy Command" : "Copy", systemImage: "doc.on.doc")
                        }
                        .controlSize(.mini)
                    }

                    if isTerminal {
                        HStack(alignment: .top, spacing: 6) {
                            Text("shivam@macbook ~ %")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(6)
                    } else {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(6)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
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

    // MARK: - Phase 2: redaction badge & non-destructive toggle (T9)

    @ViewBuilder
    private func redactionBadge(index: Int) -> some View {
        let step = session.steps[index]
        if step.isRedacted == true {
            Button(action: { toggleRedaction(at: index) }) {
                HStack(spacing: 3) {
                    Image(systemName: "shield.lefthalf.filled")
                    Text("Redacted")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.14))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Offline OCR blurred sensitive regions. Click to show the unredacted original.")
        } else if step.assets.screenshotOriginal != nil {
            Button(action: { toggleRedaction(at: index) }) {
                HStack(spacing: 3) {
                    Image(systemName: "shield.slash")
                    Text("Unredacted")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("This step has a blurred version available. Click to re-apply redaction.")
        }
    }

    /// Swaps between the blurred screenshot and the preserved original, then
    /// persists — the redaction state is what exports read.
    private func toggleRedaction(at index: Int) {
        var step = session.steps[index]

        if step.isRedacted == true {
            // Show the original, keep the blurred file for re-application.
            guard let original = step.assets.screenshotOriginal,
                  let current = step.assets.screenshot else { return }
            step.assets.screenshotOriginal = current
            step.assets.screenshot = original
            step.isRedacted = false
        } else {
            guard let original = step.assets.screenshotOriginal,
                  let current = step.assets.screenshot else { return }
            step.assets.screenshotOriginal = current
            step.assets.screenshot = original
            step.isRedacted = true
        }

        session.steps[index] = step
        try? store.saveSession(session)
    }

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
        try? store.saveSession(session)
    }

    private func deleteStep(at index: Int) {
        session.steps.remove(at: index)
        for i in session.steps.indices {
            session.steps[i].index = i + 1
        }
        try? store.saveSession(session)
    }
}
