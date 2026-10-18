import AppKit
import Foundation
import FlowlinePublishing

// MARK: - Open in editor (runtime, AppKit)
//
// Runtime counterpart to the sibling `EditorTarget` (`EditorTarget.swift`:
// identity, labels, asset names, tooltips, buttons) and to
// `FlowlinePublishing/OpenInEditorCore.swift` (bundle ids, schemes, deep-link
// builders — reused here, never duplicated). This file only does the parts
// that need NSWorkspace:
//
// - `detectInstalled()` — which `EditorTarget`s are installed, via
//   `urlForApplication(withBundleIdentifier:)` with a
//   `fullPath(forApplication:)` fallback.
// - `open(_:fileURL:line:column:)` — opens a real temp file (the caller
//   writes content first) in the target app, preferring
//   `open(_:withApplicationAt:configuration:)`; a deep-link URL is used only
//   where it adds value (positioned open at line:column for Cursor /
//   VS Code / Zed). When the target app is missing, the file is revealed in
//   Finder and a toast message is returned — never a silent drop.
// - `icon(for:appURL:size:)` — runtime app icon via
//   `icon(forFile:)` with a bundled-asset-then-SF-Symbol fallback chain
//   that reuses the sibling's `assetName` / `alternateAssetName` /
//   `fallbackSystemImage`.

/// One installed editor, as found by NSWorkspace lookup.
public struct DetectedEditor: Identifiable {
    public let target: EditorTarget
    public let appURL: URL
    public let bundleIdentifier: String
    /// Scheme resolved for the install that was found (Insiders-aware).
    public let urlScheme: String?

    public var id: String { target.rawValue }
    /// User-facing name, from the sibling `EditorTarget.label`.
    public var displayName: String { target.label }

    public init(target: EditorTarget, appURL: URL, bundleIdentifier: String, urlScheme: String?) {
        self.target = target
        self.appURL = appURL
        self.bundleIdentifier = bundleIdentifier
        self.urlScheme = urlScheme
    }
}

/// Success side of `OpenInEditors.open(_:fileURL:)`.
public enum OpenInOutcome {
    /// The file was handed to the requested editor.
    case opened(EditorTarget)
    /// The editor was missing, so the file was revealed in Finder instead.
    /// `toast` is the user-facing message to show (never silent).
    case revealedInFinder(requested: EditorTarget, toast: String)

    /// Message the UI should toast, or nil when nothing needs saying.
    public var toastMessage: String? {
        switch self {
        case .opened: return nil
        case .revealedInFinder(_, let toast): return toast
        }
    }

    public var target: EditorTarget {
        switch self {
        case .opened(let target): return target
        case .revealedInFinder(let requested, _): return requested
        }
    }
}

/// Every failure `OpenInEditors.open(_:fileURL:)` can produce, each with a
/// user-presentable `humanMessage`. No silent drops, no log spam: callers
/// surface `humanMessage` as a toast/alert.
public enum OpenInError: Error {
    case editorNotInstalled(EditorTarget)
    case fileNotFound(URL)
    case launchFailed(target: EditorTarget, appURL: URL?, reason: String)
    case deepLinkFailed(target: EditorTarget, url: URL)
    case revealFailed(URL, reason: String)

    public var humanMessage: String {
        switch self {
        case .editorNotInstalled(let target):
            return "\(target.label) isn't installed. Install it or choose another editor."
        case .fileNotFound(let url):
            return "The file \"\(url.lastPathComponent)\" no longer exists, so it can't be opened."
        case .launchFailed(let target, _, let reason):
            return "Couldn't open the file in \(target.label) (\(reason))."
        case .deepLinkFailed(let target, _):
            return "Couldn't ask \(target.label) to open this file."
        case .revealFailed(_, let reason):
            return "Couldn't reveal the file in Finder (\(reason))."
        }
    }
}

/// NSWorkspace-backed "Open in …" actions. All entry points are `@MainActor`.
@MainActor
public enum OpenInEditors {

    // MARK: - Detection

    /// Editors currently installed, in `EditorTarget.allCases` order.
    /// Finder is included when resolvable (it always is on macOS).
    public static func detectInstalled(workspace: NSWorkspace = .shared) -> [DetectedEditor] {
        EditorTarget.allCases.compactMap { locate($0, workspace: workspace) }
    }

    private static func locate(_ target: EditorTarget, workspace: NSWorkspace) -> DetectedEditor? {
        guard let info = editorLaunchInfo(forRawValue: target.rawValue) else { return nil }
        for bundleID in info.bundleIdentifiers {
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return DetectedEditor(
                    target: target,
                    appURL: appURL,
                    bundleIdentifier: bundleID,
                    urlScheme: resolvedURLScheme(for: info, bundleIdentifier: bundleID)
                )
            }
        }
        for appName in info.applicationNames {
            if let appURL = workspace.fullPath(forApplication: appName).map({ URL(fileURLWithPath: $0) }) {
                let bundleID = info.bundleIdentifiers.first ?? ""
                return DetectedEditor(
                    target: target,
                    appURL: appURL,
                    bundleIdentifier: bundleID,
                    urlScheme: resolvedURLScheme(for: info, bundleIdentifier: bundleID)
                )
            }
        }
        if target == .finder {
            let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            if FileManager.default.fileExists(atPath: finderURL.path) {
                return DetectedEditor(
                    target: .finder,
                    appURL: finderURL,
                    bundleIdentifier: EditorBundleIDs.finder,
                    urlScheme: nil
                )
            }
        }
        return nil
    }

    // MARK: - Open

    /// Opens `fileURL` in `target`.
    ///
    /// - `fileURL` must be an existing file URL (typically a temp file the
    ///   caller wrote). Missing files return `.failure(.fileNotFound)`.
    /// - Positioned opens (`line`/`column`, 1-based) use a deep link for
    ///   Cursor / VS Code / Zed, where the scheme adds value; everything
    ///   else goes through `open(_:withApplicationAt:configuration:)`.
    /// - `.finder` reveals the file in Finder directly.
    /// - When the app is missing, the file is revealed in Finder and the
    ///   success case carries the toast message to show.
    /// - Launch/deep-link/reveal failures return a typed `OpenInError`
    ///   whose `humanMessage` the caller should present.
    public static func open(
        _ target: EditorTarget,
        fileURL: URL,
        line: Int? = nil,
        column: Int? = nil,
        workspace: NSWorkspace = .shared
    ) async -> Result<OpenInOutcome, OpenInError> {
        guard fileURL.isFileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure(.fileNotFound(fileURL))
        }
        guard let info = editorLaunchInfo(forRawValue: target.rawValue) else {
            return .failure(.launchFailed(target: target, appURL: nil, reason: "isn't supported in this build."))
        }

        if target == .finder {
            return reveal(fileURL, workspace: workspace)
                ? .success(.opened(.finder))
                : .failure(.revealFailed(fileURL, reason: "Finder did not respond."))
        }

        let installed = detectInstalled(workspace: workspace)
        guard let editor = installed.first(where: { $0.target == target }) else {
            if reveal(fileURL, workspace: workspace) {
                return .success(.revealedInFinder(requested: target, toast: finderFallbackToast(displayName: target.label)))
            }
            return .failure(.revealFailed(fileURL, reason: "Finder did not respond."))
        }

        let link = (line != nil) ? deepLinkURL(
            for: info,
            fileURL: fileURL,
            line: line,
            column: column,
            bundleIdentifier: editor.bundleIdentifier
        ) : nil
        if let link, workspace.open(link) {
            return .success(.opened(target))
        }
        // A known-but-unhandled deep link falls through to a direct launch
        // rather than failing outright.

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        let launched: Bool = await withCheckedContinuation { continuation in
            workspace.open([fileURL], withApplicationAt: editor.appURL, configuration: configuration) { app, _ in
                continuation.resume(returning: app != nil)
            }
        }
        if launched {
            return .success(.opened(target))
        }
        return .failure(.launchFailed(
            target: target,
            appURL: editor.appURL,
            reason: "\(target.label) did not respond."
        ))
    }

    private static func reveal(_ fileURL: URL, workspace: NSWorkspace) -> Bool {
        workspace.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
    }

    // MARK: - Icon

    /// Runtime icon for `target` at `size` points.
    ///
    /// Chain: `NSWorkspace.icon(forFile: appURL.path)` → bundled asset
    /// (sibling `assetName`, then `alternateAssetName`) → the sibling's
    /// `fallbackSystemImage` → generic document symbol. Always returns an
    /// image (never nil).
    public static func icon(
        for target: EditorTarget,
        appURL: URL? = nil,
        size: CGFloat = 32,
        workspace: NSWorkspace = .shared
    ) -> NSImage {
        let base: NSImage
        if let appURL, FileManager.default.fileExists(atPath: appURL.path) {
            base = workspace.icon(forFile: appURL.path)
        } else if let bundled = NSImage(named: target.assetName) {
            base = bundled
        } else if let alias = target.alternateAssetName, let aliased = NSImage(named: alias) {
            base = aliased
        } else if let symbol = NSImage(
            systemSymbolName: target.fallbackSystemImage,
            accessibilityDescription: target.label
        ) {
            base = symbol
        } else {
            base = NSImage(systemSymbolName: "doc", accessibilityDescription: "Document") ?? NSImage()
        }
        let sized = (base.copy() as? NSImage) ?? base
        sized.size = NSSize(width: size, height: size)
        return sized
    }
}
