import Foundation
import StepItIR

/// Normalized, platform-neutral description of *what the user acted on*.
///
/// This is the IR replacement for the macOS-native `ElementInspectionResult`
/// in every core signature. Drivers are responsible for filling it in:
/// `MacCaptureDriver` bridges AX + `NSWorkspace` results through `IRBridging`,
/// and future drivers (Web Extension, Windows) fill the same shape.
///
/// The type is `Codable` so future phases can serialize event streams verbatim
/// (`.stepit` bundle format, Phase 4).
public struct RawElementContext: Codable, Sendable, Equatable {
    /// Localized application name, e.g. `"Safari"`. Drivers should never leave
    /// this empty when they can resolve the frontmost application.
    public var appName: String
    /// Bundle identifier when known, e.g. `"com.apple.Safari"`.
    public var bundleIdentifier: String?
    /// Title of the containing window (may be empty when AX is unavailable).
    public var windowTitle: String
    /// Accessibility role, e.g. `"AXButton"`. `nil` without AX permission.
    public var role: String?
    /// Accessibility subrole, e.g. `"AXStandardWindow"`.
    public var subrole: String?
    /// Best available label for the element: title, then description.
    public var title: String?
    /// Element value (text field content, slider position, …).
    public var value: String?
    /// Placeholder text when the platform exposes one (web inputs).
    public var placeholder: String?
    /// Accessibility role description, e.g. `"button"`.
    public var roleDescription: String?
    /// `true` when the element is a password / secure field.
    ///
    /// Phase 1 only *carries* the flag through the IR; suppression and
    /// redaction logic land in Phase 2.
    public var isSecure: Bool
    /// Element frame in screen points.
    public var boundingBox: ElementRect?
    /// Containing window frame in screen points.
    public var windowBounds: ElementRect?
    /// Ordered selector fallbacks for the Phase 3 automation compilers.
    /// Phase 1 populates `.accessibility` and `.coordinates` only.
    public var selectors: [ElementSelector]

    public init(
        appName: String,
        bundleIdentifier: String? = nil,
        windowTitle: String = "",
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        placeholder: String? = nil,
        roleDescription: String? = nil,
        isSecure: Bool = false,
        boundingBox: ElementRect? = nil,
        windowBounds: ElementRect? = nil,
        selectors: [ElementSelector] = []
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.placeholder = placeholder
        self.roleDescription = roleDescription
        self.isSecure = isSecure
        self.boundingBox = boundingBox
        self.windowBounds = windowBounds
        self.selectors = selectors
    }

    /// Explicit placeholder for the case where element inspection is denied or
    /// unavailable — replaces today's magic `"Unknown App"` string.
    public static let unknown = RawElementContext(appName: "Unknown App")
}

/// One entry in the ordered selector fallback list used by Phase 3 automation
/// compilers (AX selector → test-id → XPath → coordinates).
public struct ElementSelector: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case accessibility
        case domTestID
        case ariaLabel
        case xpath
        case css
        case coordinates
    }

    public var kind: Kind
    public var value: String
    /// Lower values are tried first.
    public var priority: Int

    public init(kind: Kind, value: String, priority: Int) {
        self.kind = kind
        self.value = value
        self.priority = priority
    }
}
