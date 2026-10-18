import Foundation

// MARK: - Open-in-editor core (pure logic, no AppKit)
//
// AppKit-free on purpose: FlowlinePublishing never imports AppKit (URL opening
// goes through `URLOpener` / `/usr/bin/open`), so this file stays importable
// from FlowlineTests. The `EditorTarget` enum itself lives in the host app
// (`Sources/Flowline/UI/Flowline/Automation/EditorTarget.swift`) alongside its
// UI members (label, asset names, tooltips); this file keys all launch data
// off the target's `rawValue` so nothing is duplicated. Runtime NSWorkspace
// work lives in `OpenInEditors.swift` in the same app folder.
//
// Scheme verification notes (web-searched 2026-10-18):
// - vscode://file/{path}[:line[:col]], Insiders uses vscode-insiders://
//   (official VS Code "Opening VS Code with URLs" docs).
// - cursor:// mirrors vscode:// (cursor://file/{path}:{line}), per Cursor forum.
// - zed:// works as zed://file/{path}[:line] (confirmed by a Zed maintainer
//   on zed-industries/zed#8482).
// - sublimetext:// is the scheme requested for this feature. Note: stock
//   Sublime Text on macOS registers no URL handler itself (the community
//   `subl://open?url=file://...` form needs a third-party helper), so the
//   runtime prefers a direct NSWorkspace launch for Sublime and only builds
//   this URL for callers that explicitly want a deep link.

// MARK: - Bundle identifiers

/// Canonical bundle identifiers, in lookup-preference order per target.
public enum EditorBundleIDs {
    public static let cursor = "com.todesktop.230313mzl4w4u92"
    public static let vsCode = "com.microsoft.VSCode"
    public static let vsCodeInsiders = "com.microsoft.VSCodeInsiders"
    public static let xcode = "com.apple.dt.Xcode"
    public static let zed = "dev.zed.Zed"
    public static let sublime = "com.sublimetext.4"
    public static let finder = "com.apple.finder"

    /// Verified (Panic Nova) but intentionally unwired: the app's
    /// `EditorTarget` has no `nova` case per the feature spec, so nothing
    /// looks this up yet.
    public static let nova = "com.panic.Nova"
}

// MARK: - URL schemes

/// URL schemes used for deep links (`<scheme>://…`).
public enum EditorURLSchemes {
    public static let cursor = "cursor"
    public static let vsCode = "vscode"
    public static let vsCodeInsiders = "vscode-insiders"
    public static let zed = "zed"
    public static let sublime = "sublimetext"
}

// MARK: - Launch info

/// How a deep-link URL is shaped for one editor.
public enum DeepLinkStyle: Sendable {
    /// `<scheme>://file<path>[:line[:column]]` (Cursor, VS Code, Zed).
    case pathSuffix
    /// `<scheme>://open?url=file://<path>[&line=L][&column=C]` (Sublime).
    case sublimeOpenQuery
    /// No usable scheme: runtime uses a direct launch / reveal instead.
    case none
}

/// NSWorkspace launch data for one editor, keyed by the app's
/// `EditorTarget.rawValue`. Single source of truth for bundle ids, app
/// names, schemes, and deep-link shape. Display names, asset names, and
/// SF-Symbol fallbacks live on the app's `EditorTarget` — not duplicated here.
public struct EditorLaunchInfo: Sendable {
    /// Matches the app's `EditorTarget.rawValue` ("cursor", "vscode", …).
    public let rawValue: String
    /// Bundle ids tried in order by install detection.
    public let bundleIdentifiers: [String]
    /// App names for the `fullPath(forApplication:)` fallback lookup.
    public let applicationNames: [String]
    /// Default deep-link scheme, or nil when `deepLinkStyle == .none`.
    public let urlScheme: String?
    /// Install variant that uses a different scheme (VS Code Insiders), if any.
    public let insidersBundleID: String?
    public let insidersScheme: String?
    public let deepLinkStyle: DeepLinkStyle

    public init(
        rawValue: String,
        bundleIdentifiers: [String],
        applicationNames: [String],
        urlScheme: String?,
        insidersBundleID: String? = nil,
        insidersScheme: String? = nil,
        deepLinkStyle: DeepLinkStyle
    ) {
        self.rawValue = rawValue
        self.bundleIdentifiers = bundleIdentifiers
        self.applicationNames = applicationNames
        self.urlScheme = urlScheme
        self.insidersBundleID = insidersBundleID
        self.insidersScheme = insidersScheme
        self.deepLinkStyle = deepLinkStyle
    }
}

/// Launch info for every supported editor, in canonical button order.
public let allEditorLaunchInfos: [EditorLaunchInfo] = [
    EditorLaunchInfo(
        rawValue: "cursor",
        bundleIdentifiers: [EditorBundleIDs.cursor],
        applicationNames: ["Cursor"],
        urlScheme: EditorURLSchemes.cursor,
        deepLinkStyle: .pathSuffix
    ),
    EditorLaunchInfo(
        rawValue: "vscode",
        bundleIdentifiers: [EditorBundleIDs.vsCode, EditorBundleIDs.vsCodeInsiders],
        applicationNames: ["Visual Studio Code", "Visual Studio Code - Insiders"],
        urlScheme: EditorURLSchemes.vsCode,
        insidersBundleID: EditorBundleIDs.vsCodeInsiders,
        insidersScheme: EditorURLSchemes.vsCodeInsiders,
        deepLinkStyle: .pathSuffix
    ),
    EditorLaunchInfo(
        rawValue: "xcode",
        bundleIdentifiers: [EditorBundleIDs.xcode],
        applicationNames: ["Xcode"],
        urlScheme: nil,
        deepLinkStyle: .none
    ),
    EditorLaunchInfo(
        rawValue: "zed",
        bundleIdentifiers: [EditorBundleIDs.zed],
        applicationNames: ["Zed"],
        urlScheme: EditorURLSchemes.zed,
        deepLinkStyle: .pathSuffix
    ),
    EditorLaunchInfo(
        rawValue: "sublime",
        bundleIdentifiers: [EditorBundleIDs.sublime],
        applicationNames: ["Sublime Text"],
        urlScheme: EditorURLSchemes.sublime,
        deepLinkStyle: .sublimeOpenQuery
    ),
    EditorLaunchInfo(
        rawValue: "finder",
        bundleIdentifiers: [EditorBundleIDs.finder],
        applicationNames: ["Finder"],
        urlScheme: nil,
        deepLinkStyle: .none
    ),
]

/// Launch info for an `EditorTarget.rawValue`, or nil when unknown.
public func editorLaunchInfo(forRawValue rawValue: String) -> EditorLaunchInfo? {
    allEditorLaunchInfos.first(where: { $0.rawValue == rawValue })
}

// MARK: - Scheme resolution

/// Scheme to use for `info`, accounting for per-install variants.
/// Today that is only VS Code Insiders (`vscode-insiders://`).
public func resolvedURLScheme(for info: EditorLaunchInfo, bundleIdentifier: String?) -> String? {
    if let insiders = info.insidersBundleID,
       let insidersScheme = info.insidersScheme,
       bundleIdentifier == insiders
    {
        return insidersScheme
    }
    return info.urlScheme
}

// MARK: - Deep links

/// Builds a deep-link URL that opens `fileURL` in the editor described by
/// `info`, optionally at `line`/`column` (1-based). Returns nil when the
/// editor has no deep-link style (`.none`) or `fileURL` is not a file URL.
///
/// Rules (all covered by FlowlineTests):
/// - Non-positive lines/columns are dropped; a column without a line is dropped.
/// - `.pathSuffix`: `<scheme>://file<path>[:line[:column]]`.
/// - `.sublimeOpenQuery`: `sublimetext://open?url=file://<path>[&line=L][&column=C]`.
public func deepLinkURL(
    for info: EditorLaunchInfo,
    fileURL: URL,
    line: Int? = nil,
    column: Int? = nil,
    bundleIdentifier: String? = nil
) -> URL? {
    guard fileURL.isFileURL else { return nil }
    guard let scheme = resolvedURLScheme(for: info, bundleIdentifier: bundleIdentifier) else { return nil }
    let cleanLine = line.flatMap { $0 >= 1 ? $0 : nil }
    let cleanColumn: Int? = {
        guard cleanLine != nil else { return nil }
        return column.flatMap { $0 >= 1 ? $0 : nil }
    }()
    let encodedPath = fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileURL.path

    switch info.deepLinkStyle {
    case .pathSuffix:
        var string = "\(scheme)://file\(encodedPath)"
        if let cleanLine {
            string += ":\(cleanLine)"
            if let cleanColumn { string += ":\(cleanColumn)" }
        }
        return URL(string: string)
    case .sublimeOpenQuery:
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        var items = [URLQueryItem(name: "url", value: "file://\(encodedPath)")]
        if let cleanLine { items.append(URLQueryItem(name: "line", value: "\(cleanLine)")) }
        if let cleanColumn { items.append(URLQueryItem(name: "column", value: "\(cleanColumn)")) }
        components.queryItems = items
        return components.url
    case .none:
        return nil
    }
}

/// User-facing toast for the reveal-in-Finder fallback path.
public func finderFallbackToast(displayName: String) -> String {
    "\(displayName) isn't installed — revealed the file in Finder instead."
}
