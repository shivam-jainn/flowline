import XCTest
import Foundation
import CoreGraphics
import AppKit
@testable import StepItCore

/// Test vector for Fast-Forward code typing and language auto-detection
struct CodeTypingVector {
    let appName: String
    let bundleId: String?
    let windowTitle: String
    let codeSnippet: String
    let expectedLanguage: String
    let isCodeExpected: Bool
}

final class CLITests: XCTestCase {
    
    // MARK: - Helper to locate Scripts directory
    
    private func locateScript(relative: String) -> URL {
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: cwdURL.path) {
            return cwdURL
        }
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            let candidate = current.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return cwdURL
    }
    
    // MARK: - Test 1: taskctl Python CLI Execution & JSON Output
    
    func testTaskctlCLIExecutionAndJSONOutput() async throws {
        let scriptURL = locateScript(relative: "Scripts/taskctl.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path), "taskctl.py should exist at \(scriptURL.path)")
        
        // 1. Test taskctl list --json via CLIExecutor
        var listOutput = ""
        let listStream = CLIExecutor.shared.executeStream(
            command: "/usr/bin/python3",
            arguments: [scriptURL.path, "list", "--json"]
        )
        for try await chunk in listStream {
            listOutput += chunk
        }
        
        XCTAssertFalse(listOutput.isEmpty, "taskctl list --json output should not be empty")
        guard let listData = listOutput.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: listData) as? [[String: Any]] else {
            XCTFail("Output should be valid JSON array: \(listOutput)")
            return
        }
        XCTAssertGreaterThanOrEqual(jsonArray.count, 3, "Sprint queue should contain tasks")
        let firstTask = jsonArray.first
        XCTAssertNotNil(firstTask?["id"])
        XCTAssertNotNil(firstTask?["title"])
        XCTAssertNotNil(firstTask?["status"])
        
        // 2. Test taskctl stats --json
        var statsOutput = ""
        let statsStream = CLIExecutor.shared.executeStream(
            command: "/usr/bin/python3",
            arguments: [scriptURL.path, "stats", "--json"]
        )
        for try await chunk in statsStream {
            statsOutput += chunk
        }
        
        XCTAssertFalse(statsOutput.isEmpty)
        guard let statsData = statsOutput.data(using: .utf8),
              let statsObj = try? JSONSerialization.jsonObject(with: statsData) as? [String: Any] else {
            XCTFail("Stats output should be valid JSON object: \(statsOutput)")
            return
        }
        XCTAssertNotNil(statsObj["total"])
        XCTAssertNotNil(statsObj["completion_rate"])
    }
    
    // MARK: - Test 2: devpulse Bash CLI Diagnostics & Benchmark
    
    func testDevpulseCLIDiagnostics() async throws {
        let scriptURL = locateScript(relative: "Scripts/devpulse.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path), "devpulse.sh should exist at \(scriptURL.path)")
        
        // 1. Test devpulse doctor
        var doctorOutput = ""
        let doctorStream = CLIExecutor.shared.executeStream(
            command: "/bin/bash",
            arguments: [scriptURL.path, "doctor"]
        )
        for try await chunk in doctorStream {
            doctorOutput += chunk
        }
        
        XCTAssertTrue(doctorOutput.contains("Developer Environment Diagnostics"))
        XCTAssertTrue(doctorOutput.contains("Swift:"))
        XCTAssertTrue(doctorOutput.contains("Architecture:"))
        XCTAssertTrue(doctorOutput.contains("verified"))
        
        // 2. Test devpulse bench
        var benchOutput = ""
        let benchStream = CLIExecutor.shared.executeStream(
            command: "/bin/bash",
            arguments: [scriptURL.path, "bench", "2"]
        )
        for try await chunk in benchStream {
            benchOutput += chunk
        }
        
        XCTAssertTrue(benchOutput.contains("simulated pipeline benchmark"))
        XCTAssertTrue(benchOutput.contains("Benchmark completed successfully"))
    }
    
    // MARK: - Test 3: fetch_cli GitHub Ingestion Script
    
    func testFetchCLIScriptExecution() async throws {
        let scriptURL = locateScript(relative: "Scripts/fetch_cli.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path), "fetch_cli.sh should exist at \(scriptURL.path)")
        
        let tempTarget = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stepit_cli_fetch_\(UUID().uuidString)")
        
        var fetchOutput = ""
        let fetchStream = CLIExecutor.shared.executeStream(
            command: "/bin/bash",
            arguments: [scriptURL.path, "https://github.com/example/test-tool", tempTarget.path]
        )
        for try await chunk in fetchStream {
            fetchOutput += chunk
        }
        
        XCTAssertTrue(fetchOutput.contains("CLI Tool Ingestion Utility"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempTarget.path))
        
        try? FileManager.default.removeItem(at: tempTarget)
    }
    
    // MARK: - Test 4: Fast-Forward Typing & Language Auto-Detection
    
    let codeTypingVectors: [CodeTypingVector] = [
        CodeTypingVector(
            appName: "Visual Studio Code",
            bundleId: "com.microsoft.VSCode",
            windowTitle: "taskctl.py",
            codeSnippet: "def cmd_add(args):\n    tasks = load_tasks()\n    tasks.append({'id': 'TASK-106'})",
            expectedLanguage: "python",
            isCodeExpected: true
        ),
        CodeTypingVector(
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "zsh",
            codeSnippet: "./Scripts/taskctl.py list && ./Scripts/devpulse.sh doctor",
            expectedLanguage: "bash",
            isCodeExpected: true
        ),
        CodeTypingVector(
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitle: "PlaygroundTests.swift",
            codeSnippet: "import XCTest\nfinal class PlaygroundTests: XCTestCase {}",
            expectedLanguage: "swift",
            isCodeExpected: true
        ),
        CodeTypingVector(
            appName: "Cursor",
            bundleId: "com.todesktop.230313mzl4w4u92",
            windowTitle: "config.json",
            codeSnippet: "{\n  \"port\": 8080,\n  \"gateway\": \"openai\"\n}",
            expectedLanguage: "json",
            isCodeExpected: true
        ),
        CodeTypingVector(
            appName: "Finder",
            bundleId: "com.apple.finder",
            windowTitle: "Downloads",
            codeSnippet: "Regular desktop file copy notes",
            expectedLanguage: "text",
            isCodeExpected: false
        )
    ]
    
    func testLanguageDetectionAndCodeEnvironment() {
        let classifier = KeystrokeClassifier()
        
        for vector in codeTypingVectors {
            let isCodeEnv = classifier.isCodeEnvironment(
                appName: vector.appName,
                bundleId: vector.bundleId,
                windowTitle: vector.windowTitle
            )
            XCTAssertEqual(isCodeEnv, vector.isCodeExpected, "App \(vector.appName) code environment evaluation")
            
            let detected = classifier.detectLanguage(
                appName: vector.appName,
                windowTitle: vector.windowTitle,
                text: vector.codeSnippet
            )
            XCTAssertEqual(detected, vector.expectedLanguage, "Language detection for \(vector.appName)")
        }
    }
    
    // MARK: - Test 5: End-to-End Terminal CLI Guide Synthesis
    
    func testTerminalCLISessionGenerationAndPublishing() throws {
        let step1 = Step(
            id: "step_cli_01",
            index: 1,
            action: .typing,
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "taskctl — zsh",
            elementRole: "AXTextField",
            elementTitle: "./Scripts/taskctl.py list",
            actionDescription: "List sprint tasks via taskctl",
            userNotes: "Outputs formatted backlog table directly in terminal.",
            textBlob: "./Scripts/taskctl.py list",
            isCode: true,
            codeLanguage: "bash"
        )
        
        let step2 = Step(
            id: "step_cli_02",
            index: 2,
            action: .writeCode,
            appName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            windowTitle: "taskctl.py",
            elementRole: "AXCodeEditor",
            elementTitle: "taskctl.py",
            actionDescription: "Add automated testing ticket",
            userNotes: "Append high-priority ticket with JSON persistence.",
            textBlob: "./Scripts/taskctl.py add \"Automate playground tour\" --priority high",
            isCode: true,
            codeLanguage: "bash"
        )
        
        let session = StepSession(
            id: "sess_cli_unit_test",
            title: "Terminal CLI & Developer Toolchain Guide",
            theme: .developerDark,
            mediaMode: .hybrid,
            steps: [step1, step2]
        )
        
        // 1. Verify HTML WebDoc contains 1-click copyable code window
        let html = WebDocGenerator.shared.generateHTML(session: session)
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Terminal CLI & Developer Toolchain Guide"))
        XCTAssertTrue(html.contains("code-window-frame"))
        XCTAssertTrue(html.contains("copy-code-btn"))
        XCTAssertTrue(html.contains("taskctl.py list"))
        
        // 2. Verify Markdown contains fenced code blocks
        let md = MarkdownExporter.shared.exportMarkdown(session: session)
        XCTAssertTrue(md.contains("Terminal CLI & Developer Toolchain Guide"))
        XCTAssertTrue(md.contains("```bash"))
        XCTAssertTrue(md.contains("./Scripts/taskctl.py list"))
    }
}
