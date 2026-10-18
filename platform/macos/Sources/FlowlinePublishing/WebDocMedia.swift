import Foundation
import FlowlineIR

extension WebDocGenerator {
    /// Asset-base-URL prefix used for media `src` attributes (moved verbatim
    /// from `generateStepsHTML`; e.g. `""` → `""`, `"media"` → `"media/"`).
    func assetURLPrefix(assetBaseURL: String) -> String {
        return assetBaseURL.isEmpty ? "" : (assetBaseURL.hasSuffix("/") ? assetBaseURL : "\(assetBaseURL)/")
    }

    func actionDisplayName(_ action: ActionType) -> String {
        switch action {
        case .click: return "Click"
        case .rightClick: return "Right-Click"
        case .doubleClick: return "Double-Click"
        case .keyPress: return "Key Press"
        case .typing: return "Typing"
        case .writeCode: return "Code"
        case .appSwitch: return "App Switch"
        case .mouseDrag: return "Drag"
        case .manual: return "Action"
        }
    }
    
    func escapeHTML(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    func escapeJS(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}
