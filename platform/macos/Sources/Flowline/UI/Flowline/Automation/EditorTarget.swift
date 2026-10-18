import Foundation

/// External-editor handoff target for the generated automation files.
///
/// Asset resolution lives in `EditorIconView` (`OpenInButtons.swift`): each
/// case maps to a host-app asset-catalog name, with an SF-Symbol fallback
/// when the asset is missing. Nothing here touches the filesystem or
/// launches apps — the caller decides what `onOpen` does per target.
public enum EditorTarget: String, CaseIterable, Identifiable, Hashable {
    case cursor
    case vscode
    case xcode
    case zed
    case sublime
    case finder

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cursor: return "Cursor"
        case .vscode: return "VS Code"
        case .xcode: return "Xcode"
        case .zed: return "Zed"
        case .sublime: return "Sublime Text"
        case .finder: return "Finder"
        }
    }

    /// Host-app asset-catalog name, probed first by `EditorIconView`.
    public var assetName: String {
        switch self {
        case .cursor: return "Cursor"
        case .vscode: return "VSCode"
        case .xcode: return "Xcode"
        case .zed: return "Zed"
        case .sublime: return "SublimeText"
        case .finder: return "Finder"
        }
    }

    /// Legacy alias probed when `assetName` is missing.
    public var alternateAssetName: String? {
        switch self {
        case .finder: return "Nova"
        default: return nil
        }
    }

    /// SF-Symbol fallback rendered when no asset resolves.
    /// Each case uses a unique symbol — no duplicates across targets or
    /// hotkey/code chips (one meaning, one mark).
    public var fallbackSystemImage: String {
        switch self {
        case .cursor: return "cursorarrow"
        case .vscode: return "square.split.2x1"
        case .xcode: return "hammer.fill"
        case .zed: return "hare.fill"
        case .sublime: return "doc.plaintext.fill"
        case .finder: return "folder.fill"
        }
    }

    /// Tooltip / accessibility description for the currently shown file.
    public func tooltip(fileName: String) -> String {
        switch self {
        case .finder: return "Reveal \(fileName) in Finder"
        default: return "Open \(fileName) in \(label)"
        }
    }
}
