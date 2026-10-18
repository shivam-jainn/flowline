import XCTest
import FlowlineStorage
import FlowlineCaptureAPI
import FlowlineMacCapture
import FlowlinePublishing
import FlowlineAIGateway
import FlowlinePermissions
import FlowlineIR
import FlowlinePipeline
import FlowlineEngine
@testable import FlowlineFixtures

final class TerminalContextInspectorTests: XCTestCase {

    // MARK: - Tier 1: title parsing

    func testGhosttyTitleParsing() {
        XCTAssertEqual(
            TerminalTitlePathParser.extractPath(from: "user@hostname: ~/Code/flowline"),
            "~/Code/flowline"
        )
    }

    func testIterm2TitleParsing() {
        XCTAssertEqual(
            TerminalTitlePathParser.extractPath(from: "1. zsh (flowline) — /codebases/flowline"),
            "/codebases/flowline"
        )
        // Hyphen separator variant.
        XCTAssertEqual(
            TerminalTitlePathParser.extractPath(from: "1. zsh - /var/log"),
            "/var/log"
        )
    }

    func testWarpTitleParsing() {
        XCTAssertEqual(TerminalTitlePathParser.extractPath(from: "~/Code/flowline"), "~/Code/flowline")
        XCTAssertEqual(TerminalTitlePathParser.extractPath(from: "~/Code/flowline — zsh"), "~/Code/flowline")
        // Prompt glued to the path without a space.
        XCTAssertEqual(TerminalTitlePathParser.extractPath(from: "user@host:~/Code/flowline"), "~/Code/flowline")
    }

    func testAppleTerminalTitleWithoutPathReturnsNil() {
        XCTAssertNil(TerminalTitlePathParser.extractPath(from: "shivamjain — -zsh — 80x24"))
        XCTAssertNil(TerminalTitlePathParser.extractPath(from: "zsh"))
        XCTAssertNil(TerminalTitlePathParser.extractPath(from: ""))
    }

    func testTrailingPunctuationAndColonsAreTrimmed() {
        XCTAssertEqual(TerminalTitlePathParser.extractPath(from: "~/Code/flowline:"), "~/Code/flowline")
        XCTAssertEqual(TerminalTitlePathParser.extractPath(from: "(/tmp/build)"), "/tmp/build")
    }

    func testHomeRootAndAbsolutePathsParse() {
        XCTAssertEqual(TerminalContextInspectorTests.paths(["/var/log", "~", "/opt/homebrew"]), ["/var/log", "~", "/opt/homebrew"])
        XCTAssertNil(TerminalTitlePathParser.extractPath(from: "/"))
    }

    private static func paths(_ titles: [String]) -> [String?] {
        titles.map { TerminalTitlePathParser.extractPath(from: $0) }
    }

    // MARK: - Strategy: injected tiers

    func testTitleWinsBeforeAppleScriptAndProcesses() async {
        let inspector = TerminalContextInspector(
            appleScriptRunner: { _ in XCTFail("AppleScript must not run when the title has a path"); return nil },
            processDirectoryResolver: { _ in XCTFail("Process probe must not run when the title has a path"); return nil },
            pidResolver: { _ in nil }
        )

        let directory = await inspector.inspectCurrentDirectory(
            forApp: "com.apple.Terminal",
            pid: nil,
            windowTitle: "user@host — ~/Code/flowline"
        )
        XCTAssertEqual(directory, "~/Code/flowline")
    }

    func testAppleScriptFallbackWhenTitleHasNoPath() async {
        let inspector = TerminalContextInspector(
            appleScriptRunner: { script in
                XCTAssertTrue(script.contains("Terminal"))
                return "/codebases/flowline"
            },
            processDirectoryResolver: { _ in XCTFail("Process probe must not run when AppleScript answers"); return nil },
            pidResolver: { _ in 4242 }
        )

        let directory = await inspector.inspectCurrentDirectory(
            forApp: "com.apple.Terminal",
            pid: 4242,
            windowTitle: "user — -zsh — 80x24"
        )
        XCTAssertEqual(directory, "/codebases/flowline")
    }

    func testProcessTreeFallbackWhenTitleAndAppleScriptFail() async {
        let inspector = TerminalContextInspector(
            appleScriptRunner: { _ in nil },
            processDirectoryResolver: { pid in
                XCTAssertEqual(pid, 777)
                return "/var/log"
            },
            pidResolver: { _ in nil }
        )

        let directory = await inspector.inspectCurrentDirectory(
            forApp: "com.mitchellh.ghostty",
            pid: 777,
            windowTitle: "Ghostty"
        )
        XCTAssertEqual(directory, "/var/log")
    }

    func testAppleScriptOnlyConfiguredForTerminalAndIterm() {
        XCTAssertNotNil(TerminalContextInspector.appleScript(for: "com.apple.Terminal"))
        XCTAssertNotNil(TerminalContextInspector.appleScript(for: "com.googlecode.iterm2"))
        XCTAssertNil(TerminalContextInspector.appleScript(for: "com.mitchellh.ghostty"))
        XCTAssertNil(TerminalContextInspector.appleScript(for: nil))
    }

    func testAllTiersFailingReturnsNil() async {
        let inspector = TerminalContextInspector(
            appleScriptRunner: { _ in nil },
            processDirectoryResolver: { _ in nil },
            pidResolver: { _ in nil }
        )

        let directory = await inspector.inspectCurrentDirectory(
            forApp: "dev.warp.Warp-Stable",
            pid: nil,
            windowTitle: "Warp"
        )
        XCTAssertNil(directory)
    }
}
