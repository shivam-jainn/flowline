import Foundation

/// Successor of `TypingEventResult`: same information, IR-typed, with the
/// classification precomputed at finalization time.
public struct TypingBatchResult: Sendable {
    public var textBlob: String
    /// Normalized context (app name / window title fallbacks already applied).
    public var context: RawElementContext?
    public var classification: InputClassification
    /// Effective capture location (window center when bounds are known).
    public var location: Point2D

    public init(
        textBlob: String,
        context: RawElementContext?,
        classification: InputClassification,
        location: Point2D
    ) {
        self.textBlob = textBlob
        self.context = context
        self.classification = classification
        self.location = location
    }
}

/// Platform-free port of the legacy macOS typing aggregator: coalesces raw keystrokes into
/// text/command batches, with two cuts made in Phase 1:
///
/// 1. The debounce interval is injectable (`Configuration`).
/// 2. The app / role / window context is pulled from an injected async
///    provider instead of the shared accessibility inspector + `NSWorkspace`.
///
/// Thread-safety: internal state lives on a private serial queue; the class is
/// callable from the engine actor and from tests.
public final class TypingBatchAggregator: @unchecked Sendable {
    public struct Configuration: Sendable {
        /// Inactivity window that finalizes a normal typing block.
        public var debounceInterval: TimeInterval

        public init(debounceInterval: TimeInterval = 1.0) {
            self.debounceInterval = debounceInterval
        }
    }

    public typealias ContextProvider = @Sendable () async -> RawElementContext?

    /// Timer-driven finalization path (inactivity) for batches the engine is
    /// not explicitly awaiting.
    public var onBatchCompleted: (@Sendable (TypingBatchResult) -> Void)?

    private var buffer: String = ""
    private var lastLocation: Point2D = .zero
    private var lastKeyTime: Date = .distantPast
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.stepit.typingbatchaggregator", qos: .userInitiated)
    private let configuration: Configuration
    private let contextProvider: ContextProvider
    private let classifier = KeystrokeClassifier()

    public init(
        configuration: Configuration = Configuration(),
        contextProvider: @escaping ContextProvider
    ) {
        self.configuration = configuration
        self.contextProvider = contextProvider
    }

    public var hasPendingText: Bool {
        queue.sync {
            !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Ingestion (parity: appendKeystroke / handleBackspace / handleReturnKey / handleControlC)

    public func append(char: String, at location: Point2D) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Cancel prior pending finalization
            self.debounceWorkItem?.cancel()

            self.buffer += char
            self.lastLocation = location
            self.lastKeyTime = Date()

            let workItem = DispatchWorkItem { [weak self] in
                self?.finalizeBuffer(at: location)
            }
            self.debounceWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.configuration.debounceInterval, execute: workItem)
        }
    }

    public func handleBackspace(at location: Point2D) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.buffer.isEmpty {
                self.buffer.removeLast()
            }
            self.lastLocation = location
            self.debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.finalizeBuffer(at: location)
            }
            self.debounceWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.configuration.debounceInterval, execute: workItem)
        }
    }

    /// Enter / Return finalizes the command / line immediately.
    public func handleReturn(at location: Point2D) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.finalizeBuffer(at: location)
        }
    }

    /// Control+C (Terminal SIGINT) appends the `^C` marker and finalizes.
    public func handleControlC(at location: Point2D) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            if self.buffer.isEmpty {
                self.buffer = "^C"
            } else {
                self.buffer += " ^C"
            }
            self.finalizeBuffer(at: location)
        }
    }

    /// The **only** flush API (replaces `forceFinalizeSynchronously`'s
    /// `queue.sync`). Returns the final batch so the engine appends it in
    /// order — no callback re-entrancy.
    public func flushPending() async -> TypingBatchResult? {
        let pending: (text: String, location: Point2D)? = await withCheckedContinuation { continuation in
            queue.async {
                self.debounceWorkItem?.cancel()
                self.debounceWorkItem = nil
                let text = self.buffer
                self.buffer = ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: (text, self.lastLocation))
                }
            }
        }

        guard let pending = pending else { return nil }
        return await makeResult(text: pending.text, location: pending.location)
    }

    // MARK: - Finalization

    /// Runs on the internal queue. Grabs the buffer and resolves the async
    /// context off-queue, then delivers through `onBatchCompleted`.
    private func finalizeBuffer(at location: Point2D) {
        let text = buffer
        buffer = ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.makeResult(text: text, location: location)
            self.onBatchCompleted?(result)
        }
    }

    private func makeResult(text: String, location: Point2D) async -> TypingBatchResult {
        let rawContext = await contextProvider()

        // Parity with the legacy aggregator's finalizeBatch: resolve app / window
        // fallbacks before classification so the terminal/code predicates see
        // the same strings as before.
        var context = rawContext ?? RawElementContext.unknown
        if context.appName.isEmpty || context.appName == RawElementContext.unknown.appName {
            context.appName = "Terminal"
        }
        if context.windowTitle.isEmpty {
            context.windowTitle = context.appName
        }

        let classification = classifier.classify(text: text, context: context)

        // Calculate center coordinate of focused window if available, otherwise
        // the recorded keystroke location.
        var effectiveLocation = location
        if let bounds = context.windowBounds, bounds.width > 50, bounds.height > 50 {
            effectiveLocation = Point2D(x: bounds.x + bounds.width / 2.0, y: bounds.y + bounds.height / 2.0)
        }

        return TypingBatchResult(
            textBlob: text,
            context: context,
            classification: classification,
            location: effectiveLocation
        )
    }
}
