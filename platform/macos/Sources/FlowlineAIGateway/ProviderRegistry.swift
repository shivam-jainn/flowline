import Foundation
import FlowlineIR

/// AI provider registry — same shape as the other two registries (Phase R §2).
public final class ProviderRegistry: @unchecked Sendable {
    private var entries: [String: (manifest: PluginManifest, factory: () -> AnyObject)] = [:]
    private let lock = NSLock()
    public init() {}
    public func register(manifest: PluginManifest, factory: @escaping () -> AnyObject) {
        lock.lock(); defer { lock.unlock() }
        entries[manifest.id] = (manifest, factory)
    }
    public func resolve(id: String, hostVersion: String = "r-m1") -> AnyObject? {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[id], e.manifest.validateHost(version: hostVersion) else { return nil }
        return e.factory()
    }
    public var registeredIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(entries.keys).sorted()
    }
}
