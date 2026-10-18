import Foundation
import FlowlineIR

/// Capture-driver registry (Phase R §2). Drivers register a factory + manifest
/// at the composition root; call sites resolve by id and never name concretes.
/// Deliberately type-erased (`AnyObject` factory) so this target stays
/// independent of the concrete `CaptureDriver` protocol (still in FlowlineCore
/// until m1-05 moves it). m1-05/m1-07 bind the real driver type without
/// changing this registry's shape.
public final class DriverRegistry: @unchecked Sendable {
    public struct Entry: Sendable {
        public var manifest: PluginManifest
        public var factory: @Sendable () -> AnyObject
        public init(manifest: PluginManifest, factory: @Sendable @escaping () -> AnyObject) {
            self.manifest = manifest
            self.factory = factory
        }
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    public init() {}

    public func register(manifest: PluginManifest, factory: @Sendable @escaping () -> AnyObject) {
        lock.lock(); defer { lock.unlock() }
        entries[manifest.id] = Entry(manifest: manifest, factory: factory)
    }

    public func resolve(id: String, hostVersion: String = "r-m1") -> AnyObject? {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[id], e.manifest.validateHost(version: hostVersion) else { return nil }
        return e.factory()
    }

    public func manifest(id: String) -> PluginManifest? {
        lock.lock(); defer { lock.unlock() }
        return entries[id]?.manifest
    }

    public var registeredIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(entries.keys).sorted()
    }
}
