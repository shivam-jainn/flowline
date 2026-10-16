import Foundation
import AppKit
import ApplicationServices

public struct TypingEventResult: Sendable {
    public var textBlob: String
    public var appName: String
    public var bundleIdentifier: String?
    public var windowTitle: String
    public var isCode: Bool
    public var language: String?
    public var location: CGPoint
    
    public init(
        textBlob: String,
        appName: String,
        bundleIdentifier: String? = nil,
        windowTitle: String = "",
        isCode: Bool = false,
        language: String? = nil,
        location: CGPoint = .zero
    ) {
        self.textBlob = textBlob
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.isCode = isCode
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
    public var debounceInterval: TimeInterval = 1.2 // 1.2s of inactivity finalizes the typing block
    
    public init() {}
    
    public func appendKeystroke(_ char: String, at location: CGPoint) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel prior pending finalization
            self.debounceWorkItem?.cancel()
            
            self.buffer += char
            self.lastKeyTime = Date()
            
            let workItem = DispatchWorkItem { [weak self] in
                self?.finalizeBatch(at: location)
            }
            self.debounceWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
    }
    
    public func forceFinalize(at location: CGPoint) {
        queue.async { [weak self] in
            self?.debounceWorkItem?.cancel()
            self?.finalizeBatch(at: location)
        }
    }
    
    private func finalizeBatch(at location: CGPoint) {
        guard !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            buffer = ""
            return
        }
        
        let typedText = buffer
        buffer = ""
        
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Editor"
        let bundleId = frontApp?.bundleIdentifier
        
        // Inspect active element or focused text
        let inspection = AccessibilityInspector.shared.inspectElement(at: location)
        var windowTitle = inspection.windowTitle
        if windowTitle.isEmpty {
            windowTitle = frontApp?.localizedName ?? ""
        }
        
        let isCodeEditor = isCodeEnvironment(appName: appName, bundleId: bundleId, windowTitle: windowTitle)
        let language = detectLanguage(appName: appName, windowTitle: windowTitle, text: typedText)
        
        let result = TypingEventResult(
            textBlob: typedText,
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            isCode: isCodeEditor,
            language: language,
            location: location
        )
        
        onTypingBatchCompleted?(result)
    }
    
    public func isCodeEnvironment(appName: String, bundleId: String?, windowTitle: String) -> Bool {
        let name = appName.lowercased()
        let bId = (bundleId ?? "").lowercased()
        let title = windowTitle.lowercased()
        
        if name.contains("code") || name.contains("xcode") || name.contains("terminal") ||
           name.contains("iterm") || name.contains("sublime") || name.contains("cursor") ||
           name.contains("intellij") || name.contains("pycharm") || name.contains("webstorm") ||
           bId.contains("vscode") || bId.contains("terminal") || bId.contains("iterm") {
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
        
        if title.contains(".swift") { return "swift" }
        if title.contains(".ts") || title.contains(".tsx") { return "typescript" }
        if title.contains(".js") || title.contains(".jsx") { return "javascript" }
        if title.contains(".py") { return "python" }
        if title.contains(".rs") { return "rust" }
        if title.contains(".go") { return "go" }
        if title.contains(".json") { return "json" }
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
        if trimmed.hasPrefix("npm ") || trimmed.hasPrefix("git ") || trimmed.hasPrefix("cd ") || trimmed.hasPrefix("curl ") { return "bash" }
        
        return "text"
    }
}
