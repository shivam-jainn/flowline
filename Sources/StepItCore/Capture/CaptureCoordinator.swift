import Foundation
import AppKit
import Combine

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording
    case paused
}

public final class CaptureCoordinator: ObservableObject, @unchecked Sendable {
    public static let shared = CaptureCoordinator()
    
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var currentSession: StepSession?
    @Published public private(set) var stepCount: Int = 0
    @Published public private(set) var recordingDuration: TimeInterval = 0
    
    private var timer: Timer?
    private var lastEventTime: Date = .distantPast
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
        
        EventMonitor.shared.stop()
        MicroClipRecorder.shared.stopBuffering()
        
        timer?.invalidate()
        timer = nil
        
        session.endedAt = Date()
        self.currentSession = session
        self.state = .idle
        
        try? SessionStore.shared.saveSession(session)
        return session
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
}
