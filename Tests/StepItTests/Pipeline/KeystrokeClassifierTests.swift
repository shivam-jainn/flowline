import XCTest
import StepItIR
import StepItPipeline
import StepItEngine
@testable import StepItCore

final class KeystrokeClassifierTests: XCTestCase {

    private let classifier = KeystrokeClassifier()

    // MARK: - Terminal app list parity (six terminals + Hyper)

    func testTerminalAppListParity() {
        let terminals: [(String, String)] = [
            ("Terminal", "com.apple.Terminal"),
            ("iTerm2", "com.googlecode.iterm2"),
            ("Ghostty", "com.mitchellh.ghostty"),
            ("Alacritty", "org.alacritty"),
            ("kitty", "net.kovidgoyal.kitty"),
            ("Warp", "dev.warp.Warp-Stable"),
            ("Hyper", "co.zeit.hyper")
        ]

        for (app, bundle) in terminals {
            XCTAssertTrue(
                classifier.isTerminalEnvironment(appName: app, bundleId: bundle, windowTitle: "zsh"),
                "\(app) should classify as terminal"
            )
            XCTAssertEqual(
                classifier.classify(text: "git status", context: RawEventFixtures.ctx(app: app, bundleId: bundle)),
                .terminal
            )
        }
    }

    func testTerminalDetectionByWindowTitle() {
        XCTAssertTrue(classifier.isTerminalEnvironment(
            appName: "Visual Studio Code",
            bundleId: "com.microsoft.VSCode",
            windowTitle: "project — zsh"
        ))
        XCTAssertTrue(classifier.isTerminalEnvironment(
            appName: "Unknown",
            bundleId: nil,
            windowTitle: "console"
        ))
        XCTAssertFalse(classifier.isTerminalEnvironment(appName: "Safari", bundleId: "com.apple.Safari", windowTitle: "GitHub"))
    }

    // MARK: - Code editor classification

    func testCodeEditorClassification() {
        let editors: [(String, String?)] = [
            ("Visual Studio Code", "com.microsoft.VSCode"),
            ("Xcode", "com.apple.dt.Xcode"),
            ("Cursor", "com.todesktop.230313mzl4w4u92"),
            ("IntelliJ IDEA", "com.jetbrains.intellij"),
            ("PyCharm", "com.jetbrains.pycharm"),
            ("WebStorm", "com.jetbrains.WebStorm"),
            ("Sublime Text", "com.sublimetext.4")
        ]

        for (app, bundle) in editors {
            XCTAssertTrue(
                classifier.isCodeEnvironment(appName: app, bundleId: bundle, windowTitle: "main"),
                "\(app) should classify as a code environment"
            )
        }

        // File-extension fallback in the window title.
        XCTAssertTrue(classifier.isCodeEnvironment(appName: "Preview", bundleId: nil, windowTitle: "readme.yaml"))
        XCTAssertTrue(classifier.isCodeEnvironment(appName: "Preview", bundleId: nil, windowTitle: "index.tsx"))
        XCTAssertFalse(classifier.isCodeEnvironment(appName: "Finder", bundleId: "com.apple.finder", windowTitle: "Documents"))
    }

    // MARK: - Language detection parity

    func testLanguageDetectionParity() {
        XCTAssertEqual(classifier.detectLanguage(appName: "Visual Studio Code", windowTitle: "workflow.py", text: "def foo(): pass"), "python")
        XCTAssertEqual(classifier.detectLanguage(appName: "Xcode", windowTitle: "App.swift", text: "import SwiftUI"), "swift")
        XCTAssertEqual(classifier.detectLanguage(appName: "Terminal", windowTitle: "bash", text: "npm install"), "bash")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "index.ts", text: "const x = 1;"), "typescript")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "config.json", text: "{\"a\": 1}"), "json")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "main.rs", text: "fn main() {}"), "rust")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "server.go", text: "package main"), "go")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "ci.yml", text: "on: push"), "yaml")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "query.sql", text: "SELECT 1"), "sql")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "page.html", text: "<div/>"), "html")
        XCTAssertEqual(classifier.detectLanguage(appName: "Cursor", windowTitle: "styles.css", text: "body {}"), "css")
    }

    func testLanguageDetectionTextStructureFallback() {
        XCTAssertEqual(classifier.detectLanguage(appName: "Notes", windowTitle: "Untitled", text: "  { \"a\": 1 }"), "json")
        XCTAssertEqual(classifier.detectLanguage(appName: "Notes", windowTitle: "Untitled", text: "import Foundation"), "swift")
        XCTAssertEqual(classifier.detectLanguage(appName: "Notes", windowTitle: "Untitled", text: "def run():"), "python")
        XCTAssertEqual(classifier.detectLanguage(appName: "Notes", windowTitle: "Untitled", text: "npm run build"), "bash")
        // Legacy "text" fallback is preserved for byte-identical step JSON.
        XCTAssertEqual(classifier.detectLanguage(appName: "Notes", windowTitle: "Untitled", text: "just some notes"), "text")
    }

    // MARK: - Classification outcomes

    func testClassifyOutcomes() {
        XCTAssertEqual(
            classifier.classify(text: "git status", context: RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty")),
            .terminal
        )
        XCTAssertEqual(
            classifier.classify(text: "let x = 1", context: RawEventFixtures.ctx(app: "Visual Studio Code", windowTitle: "main.swift")),
            .code(language: "swift")
        )
        // Code editor with no language signal keeps the legacy "text" tag.
        XCTAssertEqual(
            classifier.classify(text: "hello", context: RawEventFixtures.ctx(app: "Xcode", windowTitle: "Untitled")),
            .code(language: "text")
        )
        XCTAssertEqual(
            classifier.classify(text: "hello", context: RawEventFixtures.ctx(app: "Notes", windowTitle: "Draft")),
            .text
        )
        XCTAssertEqual(classifier.classify(text: "hello", context: nil), .text)
    }

    // MARK: - Command prefixes

    func testCommandPrefixVocabulary() {
        XCTAssertEqual(classifier.commandPrefix(in: "git status"), "git")
        XCTAssertEqual(classifier.commandPrefix(in: "npm run build"), "npm")
        XCTAssertEqual(classifier.commandPrefix(in: "  swift build"), "swift")
        XCTAssertEqual(classifier.commandPrefix(in: "cd /tmp"), "cd")
        XCTAssertEqual(classifier.commandPrefix(in: "curl https://example.com"), "curl")
        XCTAssertEqual(classifier.commandPrefix(in: "docker compose up"), "docker")
        XCTAssertNil(classifier.commandPrefix(in: "echo hello"))
    }
}
