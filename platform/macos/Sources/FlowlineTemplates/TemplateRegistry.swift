import Foundation

/// Template registry — mirrors ExporterRegistry shape (Phase R §2).
///
/// No `shared` singleton: the composition root builds one via
/// `withDefaults()` and injects it (see tooling/ci/check_architecture.sh).
public final class TemplateRegistry: @unchecked Sendable {
    private var entries: [String: GuideTemplate] = [:]
    private let lock = NSLock()

    public init() {}

    public func register(_ template: GuideTemplate) {
        lock.lock(); defer { lock.unlock() }
        entries[template.id] = template
    }

    public func resolve(id: String) -> GuideTemplate? {
        lock.lock(); defer { lock.unlock() }
        return entries[id]
    }

    public var allIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(entries.keys).sorted()
    }

    /// Registry preloaded with the built-in catalogue (`GuideTemplate.all`).
    public static func withDefaults() -> TemplateRegistry {
        let registry = TemplateRegistry()
        for template in GuideTemplate.all {
            registry.register(template)
        }
        return registry
    }
}
