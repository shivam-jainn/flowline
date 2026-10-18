import XCTest
import FlowlinePublishing

/// Pure-logic coverage for the Open-in-editor feature
/// (`Sources/FlowlinePublishing/OpenInEditorCore.swift`).
///
/// Only AppKit-free core is tested here: scheme/URL construction and
/// per-target metadata sanity. `EditorTarget` itself, NSWorkspace
/// detection/launch, and icon lookup live in the host app
/// (`Sources/Flowline/UI/Flowline/Automation/`) and are not unit-tested.
final class OpenInEditorsTests: XCTestCase {

    private func tempFile(named name: String = "snippet.swift") -> URL {
        URL(fileURLWithPath: "/tmp/flowline-open-in-\(name)")
    }

    private func info(_ rawValue: String) -> EditorLaunchInfo {
        try! XCTUnwrap(editorLaunchInfo(forRawValue: rawValue), "launch info for \(rawValue)")
    }

    // MARK: - Metadata sanity

    func testLaunchInfoTableCoversAllSixTargets() {
        XCTAssertEqual(
            allEditorLaunchInfos.map(\.rawValue),
            ["cursor", "vscode", "xcode", "zed", "sublime", "finder"]
        )
        for entry in allEditorLaunchInfos {
            XCTAssertNotNil(editorLaunchInfo(forRawValue: entry.rawValue))
            XCTAssertFalse(entry.bundleIdentifiers.isEmpty, "\(entry.rawValue) bundleIdentifiers")
            for bundleID in entry.bundleIdentifiers {
                XCTAssertTrue(bundleID.contains("."), "\(entry.rawValue) bundle id should be dotted: \(bundleID)")
            }
            XCTAssertFalse(entry.applicationNames.isEmpty, "\(entry.rawValue) applicationNames")
            if entry.deepLinkStyle == .none {
                XCTAssertNil(entry.urlScheme, "\(entry.rawValue) should have no scheme")
            } else {
                XCTAssertNotNil(entry.urlScheme, "\(entry.rawValue) should have a scheme")
            }
        }
        XCTAssertNil(editorLaunchInfo(forRawValue: "nova"))
        XCTAssertNil(editorLaunchInfo(forRawValue: ""))
    }

    func testExpectedBundleIdentifiers() {
        XCTAssertEqual(info("cursor").bundleIdentifiers, ["com.todesktop.230313mzl4w4u92"])
        XCTAssertEqual(
            info("vscode").bundleIdentifiers,
            ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        )
        XCTAssertEqual(info("xcode").bundleIdentifiers, ["com.apple.dt.Xcode"])
        XCTAssertEqual(info("zed").bundleIdentifiers, ["dev.zed.Zed"])
        XCTAssertEqual(info("sublime").bundleIdentifiers, ["com.sublimetext.4"])
        XCTAssertEqual(info("finder").bundleIdentifiers, ["com.apple.finder"])
        // Nova was verified (com.panic.Nova) but has no enum case by spec.
        XCTAssertEqual(EditorBundleIDs.nova, "com.panic.Nova")
    }

    func testDeepLinkStyles() {
        XCTAssertEqual(info("cursor").deepLinkStyle, .pathSuffix)
        XCTAssertEqual(info("vscode").deepLinkStyle, .pathSuffix)
        XCTAssertEqual(info("zed").deepLinkStyle, .pathSuffix)
        XCTAssertEqual(info("sublime").deepLinkStyle, .sublimeOpenQuery)
        XCTAssertEqual(info("xcode").deepLinkStyle, .none)
        XCTAssertEqual(info("finder").deepLinkStyle, .none)
    }

    // MARK: - Scheme resolution

    func testResolvedSchemes() {
        XCTAssertEqual(resolvedURLScheme(for: info("cursor"), bundleIdentifier: nil), "cursor")
        XCTAssertEqual(resolvedURLScheme(for: info("vscode"), bundleIdentifier: "com.microsoft.VSCode"), "vscode")
        XCTAssertEqual(
            resolvedURLScheme(for: info("vscode"), bundleIdentifier: "com.microsoft.VSCodeInsiders"),
            "vscode-insiders"
        )
        XCTAssertEqual(resolvedURLScheme(for: info("zed"), bundleIdentifier: nil), "zed")
        XCTAssertEqual(resolvedURLScheme(for: info("sublime"), bundleIdentifier: nil), "sublimetext")
        XCTAssertNil(resolvedURLScheme(for: info("xcode"), bundleIdentifier: nil))
        XCTAssertNil(resolvedURLScheme(for: info("finder"), bundleIdentifier: nil))
    }

    // MARK: - Deep links

    func testCursorDeepLink() {
        let url = deepLinkURL(for: info("cursor"), fileURL: tempFile(), line: 12, column: 3)
        XCTAssertEqual(url?.absoluteString, "cursor://file/tmp/flowline-open-in-snippet.swift:12:3")
        XCTAssertEqual(url?.scheme, "cursor")
    }

    func testVSCodeDeepLink() {
        let plain = deepLinkURL(for: info("vscode"), fileURL: tempFile())
        XCTAssertEqual(plain?.absoluteString, "vscode://file/tmp/flowline-open-in-snippet.swift")

        let positioned = deepLinkURL(for: info("vscode"), fileURL: tempFile(), line: 5, column: 10)
        XCTAssertEqual(positioned?.absoluteString, "vscode://file/tmp/flowline-open-in-snippet.swift:5:10")

        let insiders = deepLinkURL(
            for: info("vscode"),
            fileURL: tempFile(),
            line: 5,
            bundleIdentifier: "com.microsoft.VSCodeInsiders"
        )
        XCTAssertEqual(insiders?.absoluteString, "vscode-insiders://file/tmp/flowline-open-in-snippet.swift:5")
    }

    func testZedDeepLink() {
        let url = deepLinkURL(for: info("zed"), fileURL: tempFile(), line: 7)
        XCTAssertEqual(url?.absoluteString, "zed://file/tmp/flowline-open-in-snippet.swift:7")
        XCTAssertEqual(url?.scheme, "zed")
    }

    func testSublimeDeepLink() {
        let url = deepLinkURL(for: info("sublime"), fileURL: tempFile(), line: 7, column: 42)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "sublimetext")
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.host, "open")
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["url"], "file:///tmp/flowline-open-in-snippet.swift")
        XCTAssertEqual(query["line"], "7")
        XCTAssertEqual(query["column"], "42")
    }

    func testStyleNoneHasNoDeepLink() {
        XCTAssertNil(deepLinkURL(for: info("xcode"), fileURL: tempFile(), line: 3))
        XCTAssertNil(deepLinkURL(for: info("finder"), fileURL: tempFile()))
    }

    func testNonFileURLHasNoDeepLink() {
        let web = URL(string: "https://example.com/snippet.swift")!
        XCTAssertNil(deepLinkURL(for: info("vscode"), fileURL: web, line: 1))
    }

    func testLineColumnSanitization() {
        // Non-positive lines/columns are dropped.
        XCTAssertEqual(
            deepLinkURL(for: info("vscode"), fileURL: tempFile(), line: 0, column: -2)?.absoluteString,
            "vscode://file/tmp/flowline-open-in-snippet.swift"
        )
        // A column without a line is dropped.
        XCTAssertEqual(
            deepLinkURL(for: info("cursor"), fileURL: tempFile(), column: 4)?.absoluteString,
            "cursor://file/tmp/flowline-open-in-snippet.swift"
        )
        // A line without a column is fine.
        XCTAssertEqual(
            deepLinkURL(for: info("zed"), fileURL: tempFile(), line: 9)?.absoluteString,
            "zed://file/tmp/flowline-open-in-snippet.swift:9"
        )
    }

    func testPathsArePercentEncoded() {
        let spaced = URL(fileURLWithPath: "/tmp/my guide/snippet one.swift")
        let url = deepLinkURL(for: info("vscode"), fileURL: spaced, line: 2)
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.absoluteString, "vscode://file/tmp/my%20guide/snippet%20one.swift:2")

        let spacedSublime = deepLinkURL(for: info("sublime"), fileURL: spaced, line: 2)
        let query = URLComponents(url: spacedSublime!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "url" })?.value, "file:///tmp/my%20guide/snippet%20one.swift")
    }

    // MARK: - Toast

    func testFinderFallbackToast() {
        let toast = finderFallbackToast(displayName: "Cursor")
        XCTAssertTrue(toast.contains("Cursor"))
        XCTAssertTrue(toast.contains("Finder"))
    }
}
