import Foundation
import FlowlinePublishing

// MARK: - Onboarding defaults (the "onboarding phase")
//
// The first-run flow ends in an explicit setup step where the user picks
// the visuals every new guide starts from: halo kind, keycap + mouse
// styles, accent, media treatment, numbering, auto-halo. Those picks live
// here — UserDefaults-backed, tolerant-decode — and `FlowlineMetaStore`
// falls back to them whenever a session has no per-guide override yet.
// Editing them later (Settings → Onboarding) changes only *new* guides;
// existing guides keep their own stored style.

public struct OnboardingDefaults: Codable, Equatable, @unchecked Sendable {
    public var defaultHalo: FlowlineHaloKind
    public var keycapStyle: KeycapStyle
    public var mouseStyle: MouseStyle
    public var accent: FlowAccentChoice
    public var media: FlowMediaTreatment
    public var numbering: FlowNumbering
    public var autoHalo: Bool

    public init(
        defaultHalo: FlowlineHaloKind = .click,
        keycapStyle: KeycapStyle = .mac3D,
        mouseStyle: MouseStyle = .mac3D,
        accent: FlowAccentChoice = .blue,
        media: FlowMediaTreatment = .rounded,
        numbering: FlowNumbering = .numeric,
        autoHalo: Bool = true
    ) {
        self.defaultHalo = defaultHalo
        self.keycapStyle = keycapStyle
        self.mouseStyle = mouseStyle
        self.accent = accent
        self.media = media
        self.numbering = numbering
        self.autoHalo = autoHalo
    }

    private enum Keys: String, CodingKey {
        case defaultHalo, keycapStyle, mouseStyle, accent, media, numbering, autoHalo
    }

    /// Tolerant decode: older / partial payloads fall back per-field.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        defaultHalo = try c.decodeIfPresent(FlowlineHaloKind.self, forKey: .defaultHalo) ?? .click
        keycapStyle = try c.decodeIfPresent(KeycapStyle.self, forKey: .keycapStyle) ?? .mac3D
        mouseStyle = try c.decodeIfPresent(MouseStyle.self, forKey: .mouseStyle) ?? .mac3D
        accent = try c.decodeIfPresent(FlowAccentChoice.self, forKey: .accent) ?? .blue
        media = try c.decodeIfPresent(FlowMediaTreatment.self, forKey: .media) ?? .rounded
        numbering = try c.decodeIfPresent(FlowNumbering.self, forKey: .numbering) ?? .numeric
        autoHalo = try c.decodeIfPresent(Bool.self, forKey: .autoHalo) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(defaultHalo, forKey: .defaultHalo)
        try c.encode(keycapStyle, forKey: .keycapStyle)
        try c.encode(mouseStyle, forKey: .mouseStyle)
        try c.encode(accent, forKey: .accent)
        try c.encode(media, forKey: .media)
        try c.encode(numbering, forKey: .numbering)
        try c.encode(autoHalo, forKey: .autoHalo)
    }

    /// The `FlowGuideStyle` every new guide starts from.
    public func guideStyle() -> FlowGuideStyle {
        var g = FlowGuideStyle()
        g.defaultHalo = defaultHalo
        g.keycapStyle = keycapStyle
        g.mouseStyle = mouseStyle
        g.accent = accent
        g.media = media
        g.numbering = numbering
        g.autoHalo = autoHalo
        return g
    }
}

// MARK: - Persistence (UserDefaults, versioned key)

public enum OnboardingDefaultsStore {
    static let key = "com.flowline.onboarding.defaults.v1"

    public static func load() -> OnboardingDefaults {
        guard let d = UserDefaults.standard.data(forKey: key),
              let v = try? JSONDecoder().decode(OnboardingDefaults.self, from: d) else {
            return OnboardingDefaults()
        }
        return v
    }

    public static func save(_ v: OnboardingDefaults) {
        if let d = try? JSONEncoder().encode(v) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
