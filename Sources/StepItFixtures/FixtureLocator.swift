import Foundation

/// Locates the repository fixture tree (`Fixtures/`) used by the fixture-driven
/// demo tooling in this module: the Playground web app rendered by
/// `PlaygroundPageRenderer` and the demo sessions produced by
/// `DemoSessionGenerator` / `AutomatedWorkflowRecorder`.
///
/// Resolution order (first hit wins):
///   1. `STEPIT_FIXTURES_DIR` environment variable (explicit override, CI).
///   2. Walking up from the process working directory.
///   3. Walking up from this source file (Xcode / DerivedData checkouts).
///   4. `Fixtures/` inside the app bundle's resources.
public enum FixtureLocator {

    /// Directory name of the fixture tree at the repository root.
    public static let fixturesDirectoryName = "Fixtures"

    /// Fixture sub-directory holding the 10-page Playground web app.
    public static let playgroundWebDirectoryName = "playground-web"

    /// Environment variable that overrides fixture discovery.
    public static let overridesEnvironmentKey = "STEPIT_FIXTURES_DIR"

    /// Entry point every fixture lookup is validated against.
    private static let entryPointFile = "index.html"

    /// Root of the fixture tree, or `nil` when no valid fixture tree is reachable.
    public static func fixturesDirectory() -> URL? {
        if let override = ProcessInfo.processInfo.environment[overridesEnvironmentKey],
           !override.isEmpty {
            let candidate = URL(fileURLWithPath: override, isDirectory: true)
            if isValidFixturesDirectory(candidate) {
                return candidate
            }
        }

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if let found = findFixtures(startingAt: workingDirectory) {
            return found
        }

        let sourceFile = URL(fileURLWithPath: #filePath, isDirectory: false)
        if let found = findFixtures(startingAt: sourceFile) {
            return found
        }

        if let resources = Bundle.main.resourceURL, let found = findFixtures(startingAt: resources) {
            return found
        }

        return nil
    }

    /// Directory of the Playground web app (`Fixtures/playground-web`), or `nil` when absent.
    public static func playgroundWebDirectory() -> URL? {
        guard let root = fixturesDirectory() else { return nil }
        let directory = root.appendingPathComponent(playgroundWebDirectoryName, isDirectory: true)
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(entryPointFile).path)
            ? directory
            : nil
    }

    // MARK: - Private

    private static func isValidFixturesDirectory(_ candidate: URL) -> Bool {
        let entryPoint = candidate
            .appendingPathComponent(playgroundWebDirectoryName, isDirectory: true)
            .appendingPathComponent(entryPointFile)
        return FileManager.default.fileExists(atPath: entryPoint.path)
    }

    private static func findFixtures(startingAt start: URL) -> URL? {
        var current = start.hasDirectoryPath ? start : start.deletingLastPathComponent()
        while true {
            let candidate = current.appendingPathComponent(fixturesDirectoryName, isDirectory: true)
            if isValidFixturesDirectory(candidate) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }
}
