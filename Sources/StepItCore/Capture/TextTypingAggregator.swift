import Foundation
import AppKit
import ApplicationServices

public struct TypingEventResult: Sendable {
    public var textBlob: String
    public var appName: String
    public var bundleIdentifier: String?
    public var windowTitle: String
    public var isCode: Bool
    public var isTerminal: Bool
    public var language: String?
    public var location: CGPoint
    
    public init(
        textBlob: String,
        appName: String,
        bundleIdentifier: String? = nil,
        windowTitle: String = "",
        isCode: Bool = false,
        isTerminal: Bool = false,
        language: String? = nil,
        location: CGPoint = .zero
    ) {
        self.textBlob = textBlob
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.isCode = isCode
        self.isTerminal = isTerminal
        self.language = language
        self.location = location
    }
}

public final class TextTypingAggregator: @unchecked Sendable {
    public static let shared = TextTypingAggregator()
    
    private var buffer: String = ""
    private var lastKeyTime: Date = .distantPast
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.stepit.typingaggregator", qos: .userInitiated)
    
    public var onTypingBatchCompleted: ((TypingEventResult) -> Void)?
    public var debounceInterval: TimeInterval = 1.0 // 1.0s of inactivity finalizes normal typing blocks
    
    public init() {}
    
    public var hasPendingText: Bool {
        return queue.sync {
            !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    public func appendKeystroke(_ char: String, at location: CGPoint) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel prior pending finalization
            self.debounceWorkItem?.cancel()
            
            self.buffer += char
            self.lastKeyTime = Date()
            
            let workItem = DispatchWorkItem { [weak self] in
                self?.finalizeBatch(at: location, wasEnterPressed: false)
            }
            self.debounceWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
    }
    
    public func handleBackspace(at location: CGPoint) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.buffer.isEmpty {
                self.buffer.removeLast()
            }
            self.debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.finalizeBatch(at: location, wasEnterPressed: false)
            }
            self.debounceWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
    }
    
    public func handleReturnKey(at location: CGPoint) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            // When Enter / Return is pressed, immediately finalize the command / line!
            self.finalizeBatch(at: location, wasEnterPressed: true)
        }
    }
    
    public func handleControlC(at location: CGPoint) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            if self.buffer.isEmpty {
                self.buffer = "^C"
            } else {
                self.buffer += " ^C"
            }
            self.finalizeBatch(at: location, wasEnterPressed: true)
        }
    }
    
    public func forceFinalize(at location: CGPoint) {
        queue.async { [weak self] in
            self?.debounceWorkItem?.cancel()
            self?.debounceWorkItem = nil
            self?.finalizeBatch(at: location, wasEnterPressed: false)
        }
    }
    
    public func forceFinalizeSynchronously() {
        queue.sync {
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.finalizeBatch(at: NSEvent.mouseLocation, wasEnterPressed: false)
        }
    }
    
    private func finalizeBatch(at location: CGPoint, wasEnterPressed: Bool) {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            buffer = ""
            return
        }
        
        let typedText = buffer
        buffer = ""
        
        let frontApp = NSWorkspace.shared.frontmostApplication
        var appName = frontApp?.localizedName ?? "Terminal"
        var bundleId = frontApp?.bundleIdentifier
        
        // Inspect active focused element and window
        let inspection = AccessibilityInspector.shared.inspectFocusedElement()
        if !inspection.appName.isEmpty && inspection.appName != "Unknown App" {
            appName = inspection.appName
            bundleId = inspection.bundleIdentifier ?? bundleId
        }
        
        var windowTitle = inspection.windowTitle
        if windowTitle.isEmpty {
            windowTitle = frontApp?.localizedName ?? ""
        }
        
        let isTerminal = isTerminalEnvironment(appName: appName, bundleId: bundleId, windowTitle: windowTitle)
        let isCodeEditor = isTerminal || isCodeEnvironment(appName: appName, bundleId: bundleId, windowTitle: windowTitle)
        let language = isTerminal ? "bash" : detectLanguage(appName: appName, windowTitle: windowTitle, text: typedText)
        
        // Calculate center coordinate of focused window if available, otherwise mouse location
        var effectiveLocation = location
        if let bounds = inspection.windowBounds, bounds.width > 50 && bounds.height > 50 {
            effectiveLocation = CGPoint(x: bounds.x + bounds.width / 2.0, y: bounds.y + bounds.height / 2.0)
        }
        
        let result = TypingEventResult(
            textBlob: typedText,
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            isCode: isCodeEditor,
            isTerminal: isTerminal,
            language: language,
            location: effectiveLocation
        )
        
        onTypingBatchCompleted?(result)
    }
    
    public func isTerminalEnvironment(appName: String, bundleId: String?, windowTitle: String) -> Bool {
        let name = appName.lowercased()
        let bId = (bundleId ?? "").lowercased()
        let title = windowTitle.lowercased()
        
        if name.contains("terminal") || name.contains("iterm") || name.contains("alacritty") ||
           name.contains("kitty") || name.contains("warp") || name.contains("ghostty") ||
           name.contains("hyper") || bId.contains("terminal") || bId.contains("iterm") ||
           bId.contains("warp") || bId.contains("alacritty") || bId.contains("kitty") {
            return true
        }
        
        // Embedded IDE terminals or shells in window title
        if title.contains("— zsh") || title.contains("— bash") || title.contains("terminal") || title.contains("console") {
            return true
        }
        
        return false
    }
    
    public func isCodeEnvironment(appName: String, bundleId: String?, windowTitle: String) -> Bool {
        let name = appName.lowercased()
        let bId = (bundleId ?? "").lowercased()
        let title = windowTitle.lowercased()
        
        if isTerminalEnvironment(appName: appName, bundleId: bundleId, windowTitle: windowTitle) {
            return true
        }
        
        if name.contains("code") || name.contains("xcode") || name.contains("sublime") ||
           name.contains("cursor") || name.contains("intellij") || name.contains("pycharm") ||
           name.contains("webstorm") || name.contains("antigravity") ||
           bId.contains("vscode") || bId.contains("antigravity") {
            return true
        }
        
        // Check file extension in window title
        let extensions = [".swift", ".ts", ".tsx", ".js", ".jsx", ".py", ".rs", ".go", ".cpp", ".c", ".h", ".json", ".yaml", ".yml", ".sh", ".bash", ".sql", ".html", ".css"]
        for ext in extensions {
            if title.contains(ext) { return true }
        }
        
        return false
    }
    
    public func detectLanguage(appName: String, windowTitle: String, text: String) -> String {
        let name = appName.lowercased()
        let title = windowTitle.lowercased()
        
        if isTerminalEnvironment(appName: appName, bundleId: nil, windowTitle: windowTitle) {
            return "bash"
        }
        
        if title.contains(".swift") { return "swift" }
        if title.contains(".ts") || title.contains(".tsx") { return "typescript" }
        if title.contains(".json") { return "json" }
        if title.contains(".jsx") || title.contains(".js") { return "javascript" }
        if title.contains(".py") { return "python" }
        if title.contains(".rs") { return "rust" }
        if title.contains(".go") { return "go" }
        if title.contains(".yaml") || title.contains(".yml") { return "yaml" }
        if title.contains(".sql") { return "sql" }
        if title.contains(".sh") || title.contains(".bash") || name.contains("terminal") || name.contains("iterm") { return "bash" }
        if title.contains(".html") { return "html" }
        if title.contains(".css") { return "css" }
        
        // Fallback checks on text structure
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return "json" }
        if trimmed.hasPrefix("import ") || trimmed.hasPrefix("func ") || trimmed.hasPrefix("struct ") { return "swift" }
        if trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") { return "python" }
        if trimmed.hasPrefix("npm ") || trimmed.hasPrefix("git ") || trimmed.hasPrefix("cd ") || trimmed.hasPrefix("curl ") || trimmed.hasPrefix("swift ") || trimmed.hasPrefix("docker ") { return "bash" }
        
        return "text"
    }
}
