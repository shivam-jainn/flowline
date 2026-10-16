import Foundation
import AppKit
import Combine

public final class CaptureCoordinator: ObservableObject, @unchecked Sendable {
    public static let shared = CaptureCoordinator()
    
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var currentSession: StepSession?
    @Published public private(set) var stepCount: Int = 0
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var lastGestureNotice: String?
    
    private var timer: Timer?
    private var lastEventTime: Date = .distantPast
    private var gestureNoticeDismissTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "com.stepit.capturecoordinator", qos: .userInitiated)
    
    public init() {
        setupEventHandling()
    }
    
    private func setupEventHandling() {
        EventMonitor.shared.onMouseClick = { [weak self] action, point in
            self?.handleAction(action: action, at: point)
        }
        
        EventMonitor.shared.onToggleShortcut = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        
        TextTypingAggregator.shared.onTypingBatchCompleted = { [weak self] typingResult in
            self?.handleTyping(typingResult)
        }
        
        SmartGestureDetector.shared.onGestureDetected = { [weak self] notice in
            Task { @MainActor in
                self?.handleGesture(notice)
            }
        }
    }
    
    @MainActor
    public func toggleRecording() {
        switch state {
        case .idle:
            startRecording()
        case .recording, .paused:
            _ = stopRecording()
        }
    }
    
    @MainActor
    public func startRecording(
        title: String = "Workflow Recording",
        theme: ThemeName = .modernMinimal,
        mediaMode: MediaMode = .hybrid
    ) {
        guard state == .idle else { return }
        
        let session = StepSession(
            title: title,
            theme: theme,
            mediaMode: mediaMode,
            steps: []
        )
        
        self.currentSession = session
        self.stepCount = 0
        self.recordingDuration = 0
        self.state = .recording
        
        // Start duration timer
        self.timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .recording else { return }
            self.recordingDuration += 1.0
        }
        self.timer = timer
        
        // Start micro-clip buffering if needed
        if mediaMode != .staticOnly {
            MicroClipRecorder.shared.startBuffering()
        }
        
        // Sync gesture detector settings
        let loadedSettings = SessionStore.shared.loadSettings()
        SmartGestureDetector.shared.settings = loadedSettings.gestures
        
        // Start global event tap
        EventMonitor.shared.start()
        
        // Save initial session
        try? SessionStore.shared.saveSession(session)
    }
    
    @MainActor
    public func pauseRecording() {
        guard state == .recording else { return }
        state = .paused
    }
    
    @MainActor
    public func resumeRecording() {
        guard state == .paused else { return }
        state = .recording
    }
    
    @MainActor
    public func stopRecording() -> StepSession? {
        guard state != .idle, var session = currentSession else { return nil }
        
        // Synchronously flush any pending keystrokes before shutting down
        if TextTypingAggregator.shared.hasPendingText {
            TextTypingAggregator.shared.forceFinalizeSynchronously()
        }
        
        EventMonitor.shared.stop()
        MicroClipRecorder.shared.stopBuffering()
        
        timer?.invalidate()
        timer = nil
        
        session = currentSession ?? session
        session.endedAt = Date()
        self.currentSession = session
        self.state = .idle
        
        try? SessionStore.shared.saveSession(session)
        return session
    }
    
    // MARK: - Smart Gestures Actions
    
    @MainActor
    public func handleGesture(_ notice: GestureEventNotice) {
        guard state != .idle else { return }
        
        switch notice.action {
        case .none:
            break
            
        case .pauseResume:
            if state == .recording {
                pauseRecording()
                showGestureNotification("⏸️ \(notice.gestureName) → Paused")
            } else if state == .paused {
                resumeRecording()
                showGestureNotification("▶️ \(notice.gestureName) → Resumed")
            }
            
        case .stopAndReview:
            showGestureNotification("🛑 \(notice.gestureName) → Stopping & Reviewing")
            let session = stopRecording()
            if let sess = session {
                NotificationCenter.default.post(
                    name: NSNotification.Name("StepItShowReviewWindow"),
                    object: sess
                )
            }
            
        case .discardLastStep:
            discardLastStep()
            showGestureNotification("🗑️ \(notice.gestureName) → Undone Last Step")
            
        case .addCheckpoint:
            markLastStepAsCheckpoint()
            showGestureNotification("⭐ \(notice.gestureName) → Marked Checkpoint")
            
        case .captureSnapshot:
            captureInstantSnapshot(at: notice.location)
            showGestureNotification("📸 \(notice.gestureName) → Captured Snapshot")
        }
    }
    
    @MainActor
    public func showGestureNotification(_ message: String) {
        lastGestureNotice = message
        gestureNoticeDismissTask?.cancel()
        gestureNoticeDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                self.lastGestureNotice = nil
            }
        }
    }
    
    public func discardLastStep() {
        queue.async { [weak self] in
            guard let self = self, var session = self.currentSession, !session.steps.isEmpty else { return }
            _ = session.steps.removeLast()
            self.currentSession = session
            try? SessionStore.shared.saveSession(session)
            DispatchQueue.main.async {
                self.stepCount = session.steps.count
            }
        }
    }
    
    public func markLastStepAsCheckpoint() {
        queue.async { [weak self] in
            guard let self = self, var session = self.currentSession, !session.steps.isEmpty else { return }
            let lastIdx = session.steps.count - 1
            var notes = session.steps[lastIdx].userNotes ?? ""
            if !notes.contains("⭐") {
                notes = notes.isEmpty ? "⭐ Key Milestone / Checkpoint" : "⭐ [Checkpoint] \(notes)"
            }
            session.steps[lastIdx].userNotes = notes
            self.currentSession = session
            try? SessionStore.shared.saveSession(session)
        }
    }
    
    public func captureInstantSnapshot(at point: CGPoint? = nil) {
        let loc = point ?? NSEvent.mouseLocation
        handleAction(action: .manual, at: loc)
    }

    
    public func addManualStep(title: String, notes: String? = nil) {
        queue.async { [weak self] in
            guard let self = self, var session = self.currentSession, self.state == .recording else { return }
            
            let nextIndex = session.steps.count + 1
            let step = Step(
                index: nextIndex,
                timestamp: Date(),
                action: .manual,
                appName: "Manual Action",
                windowTitle: "",
                actionDescription: title,
                userNotes: notes
            )
            
            session.steps.append(step)
            self.currentSession = session
            try? SessionStore.shared.saveSession(session)
            
            DispatchQueue.main.async {
                self.stepCount = session.steps.count
            }
        }
    }
    
    private func handleAction(action: ActionType, at point: CGPoint) {
        // Flush any pending typed text/commands before recording the subsequent mouse action
        if TextTypingAggregator.shared.hasPendingText {
            TextTypingAggregator.shared.forceFinalizeSynchronously()
        }
        
        queue.async { [weak self] in
            guard let self = self, var session = self.currentSession, self.state == .recording else { return }
            
            // Debounce double trigger within 200ms
            let now = Date()
            guard now.timeIntervalSince(self.lastEventTime) > 0.20 else { return }
            self.lastEventTime = now
            
            let nextIndex = session.steps.count + 1
            
            // 1. Accessibility element inspection
            let elementInfo = AccessibilityInspector.shared.inspectElement(at: point)
            
            // 2. High-res snapshot capture with highlight
            let snapshotResult = ScreenRecorder.shared.captureScreen(
                highlightAt: point,
                stepIndex: nextIndex
            )
            
            var assets = MediaAssets()
            let filenameBase = String(format: "step_%02d", nextIndex)
            
            if let snapshot = snapshotResult {
                let pngName = "\(filenameBase).png"
                if let relPath = try? SessionStore.shared.saveMedia(
                    data: snapshot.pngData,
                    sessionID: session.id,
                    filename: pngName
                ) {
                    assets.screenshot = relPath
                }
            }
            
            // 3. Coordinate conversion
            let coords = ScreenCoordinates(x: Double(point.x), y: Double(point.y))
            
            let step = Step(
                index: nextIndex,
                timestamp: now,
                action: action,
                appName: elementInfo.appName,
                bundleIdentifier: elementInfo.bundleIdentifier,
                windowTitle: elementInfo.windowTitle,
                elementRole: elementInfo.role,
                elementTitle: elementInfo.title,
                elementValue: elementInfo.value,
                coordinates: coords,
                windowBounds: elementInfo.windowBounds,
                elementBounds: elementInfo.elementBounds,
                assets: assets
            )
            
            session.steps.append(step)
            self.currentSession = session
            try? SessionStore.shared.saveSession(session)
            
            DispatchQueue.main.async {
                self.stepCount = session.steps.count
            }
            
            // 4. Capture animated micro-clip if hybrid or animated
            if session.mediaMode != .staticOnly {
                MicroClipRecorder.shared.recordClip(around: point) { gifData, videoData in
                    var updatedAssets = step.assets
                    if let gif = gifData {
                        let gifName = "\(filenameBase).gif"
                        if let relPath = try? SessionStore.shared.saveMedia(
                            data: gif,
                            sessionID: session.id,
                            filename: gifName
                        ) {
                            updatedAssets.gif = relPath
                        }
                    }
                    
                    if let video = videoData {
                        let mp4Name = "\(filenameBase).mp4"
                        if let relPath = try? SessionStore.shared.saveMedia(
                            data: video,
                            sessionID: session.id,
                            filename: mp4Name
                        ) {
                            updatedAssets.webm = relPath
                        }
                    }
                    
                    // Update step assets in session
                    self.queue.async {
                        guard var updatedSession = self.currentSession else { return }
                        if let idx = updatedSession.steps.firstIndex(where: { $0.id == step.id }) {
                            updatedSession.steps[idx].assets = updatedAssets
                            self.currentSession = updatedSession
                            try? SessionStore.shared.saveSession(updatedSession)
                        }
                    }
                }
            }
        }
    }
    
    private func handleTyping(_ result: TypingEventResult) {
        queue.async { [weak self] in
            guard let self = self, var session = self.currentSession, self.state == .recording else { return }
            
            let nextIndex = session.steps.count + 1
            let now = Date()
            
            // 1. Snapshot capture of editor
            let snapshotResult = ScreenRecorder.shared.captureScreen(
                highlightAt: result.location,
                stepIndex: nextIndex
            )
            
            var assets = MediaAssets()
            let filenameBase = String(format: "step_%02d", nextIndex)
            
            if let snapshot = snapshotResult {
                let pngName = "\(filenameBase).png"
                if let relPath = try? SessionStore.shared.saveMedia(
                    data: snapshot.pngData,
                    sessionID: session.id,
                    filename: pngName
                ) {
                    assets.screenshot = relPath
                }
            }
            
            let action: ActionType = (result.isCode || result.isTerminal) ? .writeCode : .typing
            let cleanText = result.textBlob.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let description: String
            let role: String
            let langTag: String?
            
            if result.isTerminal {
                description = "Run \"\(cleanText)\" in \(result.appName)"
                role = "AXTerminal"
                langTag = "bash"
            } else if result.isCode {
                description = "Write code in \(result.appName)"
                role = "AXCodeEditor"
                langTag = result.language
            } else {
                let preview = cleanText.prefix(32)
                description = "Type \"\(preview)\(cleanText.count > 32 ? "..." : "")\" in \(result.appName)"
                role = "AXTextField"
                langTag = nil
            }
            
            let step = Step(
                index: nextIndex,
                timestamp: now,
                action: action,
                appName: result.appName,
                bundleIdentifier: result.bundleIdentifier,
                windowTitle: result.windowTitle,
                elementRole: role,
                elementTitle: langTag != nil ? "(\(langTag!))" : nil,
                coordinates: ScreenCoordinates(x: Double(result.location.x), y: Double(result.location.y)),
                actionDescription: description,
                textBlob: result.textBlob,
                isCode: result.isCode || result.isTerminal,
                codeLanguage: result.language,
                assets: assets
            )
            
            session.steps.append(step)
            self.currentSession = session
            try? SessionStore.shared.saveSession(session)
            
            DispatchQueue.main.async {
                self.stepCount = session.steps.count
            }
            
            // 2. Generate fast-forward GIF from rolling buffer
            if session.mediaMode != .staticOnly {
                MicroClipRecorder.shared.recordClip(around: result.location, postDuration: 0.6) { gifData, _ in
                    guard let gif = gifData else { return }
                    let gifName = "\(filenameBase).gif"
                    if let relPath = try? SessionStore.shared.saveMedia(
                        data: gif,
                        sessionID: session.id,
                        filename: gifName
                    ) {
                        self.queue.async {
                            guard var updatedSession = self.currentSession else { return }
                            if let idx = updatedSession.steps.firstIndex(where: { $0.id == step.id }) {
                                updatedSession.steps[idx].assets.gif = relPath
                                self.currentSession = updatedSession
                                try? SessionStore.shared.saveSession(updatedSession)
                            }
                        }
                    }
                }
            }
        }
    }
}
