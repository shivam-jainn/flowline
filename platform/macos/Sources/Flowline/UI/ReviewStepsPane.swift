import SwiftUI
import FlowlineIR
import FlowlineStorage

/// Steps timeline + inspector pane of the review window (R/M1-07 split).
/// Mutates the session through a binding; persistence goes through the
/// injected store and Settings opens through the injected callback.
public struct ReviewStepsPane: View {
    @Binding public var session: StepSession
    public var store: SessionStore
    public var onOpenSettings: () -> Void

    @State private var selectedStepIndex: Int = 1
    @State private var showingZoomCrop: [Int: Bool] = [:]
    private func mediaChoiceBinding(for listIndex: Int) -> Binding<String> {
        Binding(
            get: {
                // Default agrees with WebDocSections: GIF when an animation
                // was captured, Static otherwise.
                if let saved = session.steps[listIndex].preferredMedia { return saved }
                if session.steps[listIndex].assets.gif != nil { return "GIF" }
                return "Static"
            },
            set: {
                session.steps[listIndex].preferredMedia = $0
                try? store.saveSession(session)
            }
        )
    }

    /// Effective per-step choice: explicit `preferredMedia`, else GIF when a
    /// gif asset exists (matching the binding default + web export default).
    private func effectiveMediaChoice(for step: Step) -> String {
        if let saved = step.preferredMedia { return saved }
        return step.assets.gif != nil ? "GIF" : "Static"
    }

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
                HStack(spacing: FlowSpacing.sm) {
                    Button(action: addManualStep) {
                        Label("Add Step", systemImage: FlowSymbols.add)
                    }
                    .controlSize(.small)

                    Button(action: onOpenSettings) {
                        Image(systemName: FlowSymbols.settings)
                    }
                    .controlSize(.small)
                    .help("Settings")
                    .accessibilityLabel("Open settings")
                }
            }
            .padding(FlowSpacing.md)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Step Cards List — even 16pt gaps, 12pt canvas padding
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FlowSpacing.lg) {
                    ForEach(session.steps.indices, id: \.self) { idx in
                        stepCard(index: idx)
                    }
                }
                .padding(FlowSpacing.md)
            }
        }
    }

    private func stepCard(index: Int) -> some View {
        let step = session.steps[index]
        let isSelected = selectedStepIndex == step.index

        return VStack(alignment: .leading, spacing: FlowSpacing.sm) {
            HStack(alignment: .top, spacing: FlowSpacing.sm) {
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
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        if !step.appName.isEmpty {
                            Label(step.appName, systemImage: "app.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let role = step.elementRole {
                            Text(role)
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, FlowSpacing.sm)
                                .padding(.vertical, FlowSpacing.xs)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(FlowComponent.radiusXS)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let combo = step.hotkeyCombo {
                            Label(combo, systemImage: "keyboard")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, FlowSpacing.sm)
                                .padding(.vertical, FlowSpacing.xs)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(FlowComponent.radiusXS)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let directory = step.workingDirectory {
                            Label(directory, systemImage: "folder")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        redactionBadge(index: index)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()

                Spacer()

                // Delete button — icon-only with 44pt hit target
                Button(action: {
                    deleteStep(at: index)
                }) {
                    Image(systemName: FlowSymbols.trash)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(FlowSpacing.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Delete step")
                .accessibilityLabel("Delete step \(step.index)")
            }

            // MediaChoice: per-step GIF vs Static image toggle (post-recording).
            // Persisted to step.preferredMedia and actually switches the preview.
            // Shown whenever an animation was captured (screenshot optional).
            if step.assets.gif != nil {
                Picker("MediaChoice", selection: mediaChoiceBinding(for: index)) {
                    Text("Static").tag("Static")
                    Text("GIF").tag("GIF")
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }

            // Thumbnail / Scrubber / 2.4x Zoom View — honors the GIF/static choice.
            // NB: SwiftUI Image(nsImage:) renders only the first GIF frame, so
            // the GIF branch uses AnimatedGIFView (NSImageView, animates=true).
            let wantsGIF = effectiveMediaChoice(for: step) == "GIF" && step.assets.gif != nil
            if wantsGIF, let gifPath = step.assets.gif {
                let gifURL = store.resolveMediaPath(sessionID: session.id, relativePath: gifPath)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Animated GIF preview")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    AnimatedGIFView(url: gifURL)
                        .frame(maxWidth: .infinity, maxHeight: 180)
                        .frame(height: 180)
                        .background(Color.black.opacity(0.15))
                        .clipped()
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            } else if let screenshotPath = step.assets.screenshot {
                let showZoom = (showingZoomCrop[step.index] ?? false) && (step.assets.zoomCrop != nil)
                let activePath = showZoom ? (step.assets.zoomCrop ?? screenshotPath) : screenshotPath
                let imgURL = store.resolveMediaPath(sessionID: session.id, relativePath: activePath)

                VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                    if step.assets.zoomCrop != nil {
                        HStack(spacing: FlowSpacing.sm) {
                            Button(action: {
                                showingZoomCrop[step.index] = false
                            }) {
                                Text("Overview")
                                    .font(.system(size: 10, weight: !showZoom ? .bold : .regular))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, FlowSpacing.sm)
                            .padding(.vertical, FlowSpacing.xs)
                            .background(!showZoom ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(FlowComponent.radiusXS)

                            Button(action: {
                                showingZoomCrop[step.index] = true
                            }) {
                                // Leading icon + label, even 4pt gap
                                HStack(spacing: FlowSpacing.xs) {
                                    Image(systemName: "plus.magnifyingglass")
                                    Text("2.4× Zoom")
                                }
                                .font(.system(size: 10, weight: showZoom ? .bold : .regular))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, FlowSpacing.sm)
                            .padding(.vertical, FlowSpacing.xs)
                            .background(showZoom ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(FlowComponent.radiusXS)

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
                            .frame(maxWidth: .infinity, maxHeight: 180)
                            .clipped()
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
                VStack(alignment: .leading, spacing: FlowSpacing.sm) {
                    HStack {
                        Label(isTerminal ? "Terminal CLI Command" : (step.isCode ? "Code Snippet (\(step.codeLanguage ?? "code"))" : "Typed Text"), systemImage: isTerminal ? "terminal.fill" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }) {
                            Label(isTerminal ? "Copy Command" : "Copy", systemImage: FlowSymbols.copy)
                        }
                        .controlSize(.small)
                    }

                    if isTerminal {
                        HStack(alignment: .top, spacing: FlowSpacing.sm) {
                            Text("$")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(FlowSpacing.sm)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(FlowComponent.radiusXS)
                    } else {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(FlowSpacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(FlowComponent.radiusXS)
                    }
                }
                .padding(FlowSpacing.sm)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(FlowSpacing.sm)
            }

            // User notes input
            TextField("Optional guidance or note for this step...", text: Binding(
                get: { session.steps[index].userNotes ?? "" },
                set: { session.steps[index].userNotes = $0 }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.06) : Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .clipped()
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
                // Leading icon + label, even 4pt gap, 8×4 padding
                HStack(spacing: FlowSpacing.xs) {
                    Image(systemName: FlowSymbols.shield)
                    Text("Redacted")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.horizontal, FlowSpacing.sm)
                .padding(.vertical, FlowSpacing.xs)
                .background(Color.orange.opacity(0.14))
                .cornerRadius(FlowComponent.radiusXS)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Offline OCR blurred sensitive regions. Click to show the unredacted original.")
        } else if step.assets.screenshotOriginal != nil {
            Button(action: { toggleRedaction(at: index) }) {
                HStack(spacing: FlowSpacing.xs) {
                    Image(systemName: FlowSymbols.shieldSlash)
                    Text("Unredacted")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, FlowSpacing.sm)
                .padding(.vertical, FlowSpacing.xs)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(FlowComponent.radiusXS)
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

// MARK: - Animated GIF preview

/// Custom NSImageView subclass that sets an explicit 180pt height while yielding
/// horizontal intrinsic width so that high-resolution GIFs (e.g. 2880x1800 Retina)
/// fit the card width without collapsing to height 0 or expanding the column.
final class DynamicSizingImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 180)
    }
}

/// Plays an animated GIF from disk. SwiftUI `Image(nsImage:)` renders only
/// the first frame, so this wraps `NSImageView` (which animates GIFs when
/// `animates = true`) via `NSViewRepresentable`.
struct AnimatedGIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = DynamicSizingImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.image = NSImage(contentsOf: url)
        context.coordinator.loadedURL = url
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image == nil || context.coordinator.loadedURL != url {
            nsView.image = NSImage(contentsOf: url)
            nsView.animates = true
            context.coordinator.loadedURL = url
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
    }
}
