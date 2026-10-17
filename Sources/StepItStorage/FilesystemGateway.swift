import Foundation

// MARK: - Filesystem gateway (owns: StepItStorage, R/M1-04)
//
// The store's only seam to the real filesystem. Production uses
// `LiveFilesystemGateway` (FileManager-backed); tests inject
// `InMemoryFilesystemGateway` and get byte-identical serialization behavior
// without touching disk.

/// Minimal file operations the session store needs. URLs are absolute.
public protocol FilesystemGateway: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func removeItem(at url: URL) throws
    func readData(at url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
}

/// Live FileManager-backed gateway.
public struct LiveFilesystemGateway: FilesystemGateway, @unchecked Sendable {
    public init() {}

    private var fileManager: FileManager { FileManager.default }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.contentModificationDateKey])
    }

    public func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

/// In-memory fake for tests. Keyed by absolute path string.
public final class InMemoryFilesystemGateway: FilesystemGateway, @unchecked Sendable {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []
    private let lock = NSLock()

    public init() {}

    public func fileExists(at url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return files[url.path] != nil || directories.contains(url.path)
    }

    public func createDirectory(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        directories.insert(url.path)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        lock.lock(); defer { lock.unlock() }
        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
        var seen: Set<String> = []
        for path in Set(files.keys).union(directories) {
            guard path.hasPrefix(prefix) else { continue }
            let rest = String(path.dropFirst(prefix.count))
            guard !rest.isEmpty else { continue }
            let first = rest.split(separator: "/").first.map(String.init) ?? rest
            seen.insert(prefix + first)
        }
        return seen.map { URL(fileURLWithPath: $0) }
    }

    public func removeItem(at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
        for key in files.keys where key == url.path || key.hasPrefix(prefix) {
            files.removeValue(forKey: key)
        }
        for key in directories where key == url.path || key.hasPrefix(prefix) {
            directories.remove(key)
        }
    }

    public func readData(at url: URL) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = files[url.path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil)
        }
        return data
    }

    public func writeData(_ data: Data, to url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        var dir = url.deletingLastPathComponent().path
        directories.insert(dir)
        // Ensure ancestor dirs exist for directory listing fidelity.
        while dir != "/" {
            dir = URL(fileURLWithPath: dir).deletingLastPathComponent().path
            directories.insert(dir)
        }
        files[url.path] = data
    }
}
