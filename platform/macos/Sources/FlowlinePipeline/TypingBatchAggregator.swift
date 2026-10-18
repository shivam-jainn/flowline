import Foundation
import FlowlineIR

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
/// text/command batches, with three cuts made across phases:
///
/// 1. The debounce interval is injectable (`Configuration`).
/// 2. The app / role / window context is pulled from an injected async
///    provider instead of the shared accessibility inspector + `NSWorkspace`.
/// 3. **Phase 2 (T6):** when the focused element is `isSecure`, raw characters
///    are *never* appended to the buffer — they become `•` masks (or are
///    dropped entirely when `PrivacySettings.maskSecureInputFields` is off).
///    This guarantees zero plaintext passwords in memory, disk or exports.
///
/// Thread-safety: state is guarded by `NSLock`; all ingestion methods are
/// `async` so the secure-field decision (which needs one AX probe per batch)
/// happens **before** the first character is buffered.
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

    private let lock = NSLock()
    private var buffer: String = ""
    private var lastLocation: Point2D = .zero
    private var debounceTask: Task<Void, Never>?
    private var privacy = PrivacySettings()

    // MARK: - Smart segmentation state (mirrors `flowline_pipeline::aggregate`)

    /// Hysteresis mode: per-app `T_LOW`/`T_HIGH` + adaptive p95 instead of the
    /// single `debounceInterval`. Rust core is the source of truth; thresholds
    /// resolve through `KeystrokeClassifier` (which delegates to `FlowlineFFI`
    /// when the bindings are present).
    private var smartSegmentation = false
    private var ikiHistory: [Double] = []
    private var lastActivity: Date?
    private var lastContext: RawElementContext?
    private var imeComposing = false
    private var clipboardHash: UInt64?

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

    /// Privacy policy (T6). Pushed by the engine at recording start / settings
    /// save so the very next keystroke sees the latest rules.
    public var privacySettings: PrivacySettings {
        get { lock.withLock { privacy } }
        set { lock.withLock { privacy = newValue } }
    }

    public var hasPendingText: Bool {
        lock.withLock {
            !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Opt into hysteresis segmentation (`T_LOW` JOIN / `T_HIGH` CUT with an
    /// ambiguous hold, per-app profiles, adaptive p95).
    public func enableSmartSegmentation() {
        lock.withLock { smartSegmentation = true }
    }

    /// IME composition gate: suspends the gap timer until commit/cancel.
    public func setComposing(_ composing: Bool) {
        lock.withLock { imeComposing = composing }
        if composing {
            cancelDebounce()
        }
    }

    public func setClipboardHash(_ hash: UInt64?) {
        lock.withLock { clipboardHash = hash }
    }

    /// Effective `(low, high)` thresholds (seconds) for `context`.
    public func effectiveThresholds(for context: RawElementContext?) -> (low: TimeInterval, high: TimeInterval) {
        let smart = lock.withLock { smartSegmentation }
        guard smart else {
            return (configuration.debounceInterval, configuration.debounceInterval)
        }
        let (lowMs, highMs) = classifier.thresholds(for: context)
        let gapsMs: [Double] = lock.withLock { ikiHistory }
        let p95ms = KeystrokeClassifier.p95(gapsMs)
        let (aLow, aHigh) = KeystrokeClassifier.adaptiveThresholds(baseLow: lowMs, baseHigh: highMs, p95: p95ms)
        return (aLow / 1000, aHigh / 1000)
    }

    // MARK: - Ingestion (parity: appendKeystroke / handleBackspace / handleReturnKey / handleControlC)

    public func append(char: String, at location: Point2D) async {
        // Probe the focused element on **every** keystroke: a focus change in
        // the middle of a batch (no debounce boundary yet) must never inherit a
        // stale "not secure" verdict and buffer raw password characters.
        let context = await contextProvider()

        // Focus-change cut (over-join killer): any bundle/window/AX-role hop
        // flushes the pending batch BEFORE the next char. `AXUnknown` popups
        // are ignorable noise and never cut.
        if let context, KeystrokeClassifier.focusChanged(from: lock.withLock({ lastContext }), to: context) {
            let pendingEmpty = lock.withLock { buffer.isEmpty }
            if !pendingEmpty {
                await finalizeBuffer(at: lock.withLock { lastLocation })
            }
        }

        let isSecure = context?.isSecure ?? false
        let shouldMask = lock.withLock { privacy.maskSecureInputFields }
        let now = Date()

        lock.withLock {
            if let last = lastActivity {
                ikiHistory.append(now.timeIntervalSince(last) * 1000)
                if ikiHistory.count > 200 {
                    ikiHistory.removeFirst(ikiHistory.count - 200)
                }
            }
            if isSecure {
                // Zero-plaintext invariant: the raw character never enters the
                // buffer — only masks (or nothing) do.
                if shouldMask {
                    buffer += String(repeating: "•", count: max(1, char.count))
                }
            } else {
                buffer += char
            }
            lastLocation = location
            lastActivity = now
            lastContext = context
        }
        armDebounce(at: location)
    }

    /// Atomic paste: one payload, never cut inside. Forces the boundary
    /// BEFORE the paste when the element changed; burst-rate follow-ups join.
    public func handlePaste(text: String, at location: Point2D, clipboardHash: UInt64? = nil) async {
        let context = await contextProvider()
        if let context, KeystrokeClassifier.focusChanged(from: lock.withLock({ lastContext }), to: context) {
            let pendingEmpty = lock.withLock { buffer.isEmpty }
            if !pendingEmpty {
                await finalizeBuffer(at: lock.withLock { lastLocation })
            }
        }
        if let hash = clipboardHash {
            lock.withLock { self.clipboardHash = hash }
        }
        let isSecure = context?.isSecure ?? false
        let shouldMask = lock.withLock { privacy.maskSecureInputFields }
        let now = Date()
        lock.withLock {
            if let last = lastActivity {
                ikiHistory.append(now.timeIntervalSince(last) * 1000)
                if ikiHistory.count > 200 {
                    ikiHistory.removeFirst(ikiHistory.count - 200)
                }
            }
            if isSecure {
                if shouldMask {
                    buffer += String(repeating: "•", count: max(1, text.count))
                }
            } else {
                buffer += text
            }
            lastLocation = location
            lastActivity = now
            lastContext = context
        }
        armDebounce(at: location)
    }

    public func handleBackspace(at location: Point2D) async {
        let now = Date()
        lock.withLock {
            if !buffer.isEmpty {
                buffer.removeLast()
            }
            lastLocation = location
            if let last = lastActivity {
                ikiHistory.append(now.timeIntervalSince(last) * 1000)
                if ikiHistory.count > 200 {
                    ikiHistory.removeFirst(ikiHistory.count - 200)
                }
            }
            lastActivity = now
        }
        armDebounce(at: location)
    }

    /// Option/Command+Backspace word-undo: deletes to the previous word
    /// boundary and keeps the batch coalesced.
    public func handleBackspaceWord(at location: Point2D) async {
        let now = Date()
        lock.withLock {
            var chars = Array(buffer)
            while chars.last?.isWhitespace == true { chars.removeLast() }
            while let last = chars.last, !last.isWhitespace { chars.removeLast() }
            while chars.last?.isWhitespace == true { chars.removeLast() }
            buffer = String(chars)
            lastLocation = location
            if let last = lastActivity {
                ikiHistory.append(now.timeIntervalSince(last) * 1000)
                if ikiHistory.count > 200 {
                    ikiHistory.removeFirst(ikiHistory.count - 200)
                }
            }
            lastActivity = now
        }
        armDebounce(at: location)
    }

    /// Enter / Return finalizes the command / line immediately.
    /// Legacy unconditional cut (terminal / single-line parity).
    public func handleReturn(at location: Point2D) async {
        cancelDebounce()
        lock.withLock {
            lastActivity = nil
            lastContext = nil
            imeComposing = false
        }
        await finalizeBuffer(at: location)
    }

    /// Smart Return: terminal / single-line / `Cmd+Return` CUT; multiline
    /// plain Return JOINs a newline into the pending batch.
    public func handleReturnSmart(at location: Point2D, commandHeld: Bool) async {
        let context = await contextProvider()
        if context?.isSecure == true {
            await handleReturn(at: location)
            return
        }
        switch classifier.classifyReturn(context, commandHeld: commandHeld) {
        case .cut:
            await handleReturn(at: location)
        case .joinNewline:
            let now = Date()
            lock.withLock {
                if let last = lastActivity {
                    ikiHistory.append(now.timeIntervalSince(last) * 1000)
                    if ikiHistory.count > 200 {
                        ikiHistory.removeFirst(ikiHistory.count - 200)
                    }
                }
                buffer += "\n"
                lastLocation = location
                lastActivity = now
                lastContext = context
            }
            armDebounce(at: location)
        }
    }

    /// Control+C (Terminal SIGINT) appends the `^C` marker and finalizes.
    public func handleControlC(at location: Point2D) async {
        cancelDebounce()
        lock.withLock {
            if buffer.isEmpty {
                buffer = "^C"
            } else {
                buffer += " ^C"
            }
            lastLocation = location
        }
        await finalizeBuffer(at: location)
    }

    /// The **only** flush API (replaces `forceFinalizeSynchronously`'s
    /// `queue.sync`). Returns the final batch so the engine appends it in
    /// order — no callback re-entrancy.
    public func flushPending() async -> TypingBatchResult? {
        let pending: (text: String, location: Point2D)? = lock.withLock {
            debounceTask?.cancel()
            debounceTask = nil
            lastActivity = nil
            lastContext = nil
            let text = buffer
            buffer = ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (text, lastLocation)
        }

        guard let pending = pending else { return nil }
        return await makeResult(text: pending.text, location: pending.location)
    }

    // MARK: - Debounce

    private func armDebounce(at location: Point2D) {
        // IME composition suspends the gap timer.
        let composing = lock.withLock { imeComposing }
        if composing { return }
        let interval: TimeInterval = lock.withLock {
            guard smartSegmentation, let last = lastActivity, let ctx = lastContext else {
                return configuration.debounceInterval
            }
            // Gap-aware hysteresis is timer-driven here: ambiguous holds are
            // realized by re-arming the HIGH bound; corroborating cuts arrive
            // via explicit focus/Return paths above.
            let (lowMs, highMs) = classifier.thresholds(for: ctx)
            let gapsMs: [Double] = ikiHistory
            let p95ms = KeystrokeClassifier.p95(gapsMs)
            let (_, high) = KeystrokeClassifier.adaptiveThresholds(baseLow: lowMs, baseHigh: highMs, p95: p95ms)
            let _ = lowMs
            let _ = last
            return high / 1000
        }
        lock.lock()
        debounceTask?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.finalizeBuffer(at: location)
        }
        debounceTask = task
        lock.unlock()
    }

    private func cancelDebounce() {
        lock.withLock {
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    // MARK: - Finalization

    /// Grabs the buffer and resolves the async context off-lock, then delivers
    /// through `onBatchCompleted`.
    private func finalizeBuffer(at location: Point2D) async {
        let text: String = lock.withLock {
            let text = buffer
            buffer = ""
            debounceTask = nil
            lastActivity = nil
            lastContext = nil
            return text
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let result = await makeResult(text: text, location: location)
        onBatchCompleted?(result)
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
        if context.isSecure {
            // Defense in depth: never let a secure field's value ride along.
            context.value = nil
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
