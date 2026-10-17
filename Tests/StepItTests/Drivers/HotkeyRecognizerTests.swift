import XCTest
import StepItStorage
import StepItCaptureAPI
import StepItMacCapture
import StepItPublishing
import StepItAIGateway
import StepItPermissions
import StepItIR
import StepItPipeline
import StepItEngine
@testable import StepItCore

final class HotkeyRecognizerTests: XCTestCase {

    private func makeRecognizer(
        settings: HotkeyCaptureSettings = HotkeyCaptureSettings(),
        toggleCombo: String = "⌥Space"
    ) -> HotkeyRecognizer {
        HotkeyRecognizer(settings: settings, toggleCombo: toggleCombo)
    }

    // MARK: - Workflow shortcuts (⌘ / ⌃ chords)

    func testCommandChordParsesToStandardizedCombo() {
        guard case let .workflowShortcut(chord) = makeRecognizer().evaluate(key: "s", code: 1, modifiers: [.command]) else {
            return XCTFail("⌘S should be a workflow shortcut")
        }
        XCTAssertEqual(chord.key, "s")
        XCTAssertEqual(chord.displayKey, "S")
        XCTAssertEqual(chord.combo, "⌘S")
        XCTAssertEqual(chord.code, 1)
        XCTAssertTrue(chord.isShortcut)
        XCTAssertTrue(chord.modifiers.contains(.command))
    }

    func testCommandShiftPCombo() {
        guard case let .workflowShortcut(chord) = makeRecognizer().evaluate(key: "P", code: 35, modifiers: [.command, .shift]) else {
            return XCTFail("⌘⇧P should be a workflow shortcut")
        }
        XCTAssertEqual(chord.combo, "⌘⇧P")
    }

    func testMultiModifierCombosRenderInCanonicalOrder() {
        let cases: [(KeyModifiers, String)] = [
            ([.command, .option], "⌘⌥I"),
            ([.command, .option, .control], "⌘⌥⌃I"),
            ([.command, .shift, .option], "⌘⌥⇧I"),
            ([.control], "⌃I")
        ]

        for (modifiers, expected) in cases {
            guard case let .workflowShortcut(chord) = makeRecognizer().evaluate(key: "i", code: 34, modifiers: modifiers) else {
                return XCTFail("Expected workflow shortcut for \(expected)")
            }
            XCTAssertEqual(chord.combo, expected)
        }
    }

    func testControlCIsClassifiedAsAWorkflowShortcut() {
        // The engine keeps ⌃C on the terminal-interrupt path (Phase 1 parity),
        // but the recognizer still classifies the chord uniformly.
        guard case let .workflowShortcut(chord) = makeRecognizer().evaluate(key: "c", code: 8, modifiers: [.control]) else {
            return XCTFail("⌃C should be a workflow shortcut")
        }
        XCTAssertEqual(chord.combo, "⌃C")
    }

    // MARK: - Navigation keys (Esc / Tab / arrows / F-keys)

    func testNavigationKeysParseToDiscreteChords() {
        let cases: [(String, Int, String)] = [
            ("Escape", 53, "Escape"),
            ("Tab", 48, "Tab"),
            ("ArrowLeft", 123, "ArrowLeft"),
            ("ArrowRight", 124, "ArrowRight"),
            ("ArrowUp", 126, "ArrowUp"),
            ("ArrowDown", 125, "ArrowDown"),
            ("F1", 122, "F1"),
            ("F12", 111, "F12"),
            ("Delete", 117, "Delete")
        ]

        for (key, code, expectedCombo) in cases {
            guard case let .navigationKey(chord) = makeRecognizer().evaluate(key: key, code: code, modifiers: []) else {
                return XCTFail("\(key) should be a navigation key")
            }
            XCTAssertEqual(chord.combo, expectedCombo)
            XCTAssertFalse(chord.isShortcut)
        }
    }

    func testShiftTabIsBackwardsNavigation() {
        guard case let .navigationKey(chord) = makeRecognizer().evaluate(key: "Tab", code: 48, modifiers: [.shift]) else {
            return XCTFail("⇧Tab should be a navigation key")
        }
        XCTAssertEqual(chord.combo, "⇧Tab")
    }

    func testFunctionFlagFromArrowKeysIsNotRendered() {
        // macOS sets `.function` on arrow events even when `fn` was not pressed.
        guard case let .navigationKey(chord) = makeRecognizer().evaluate(key: "ArrowDown", code: 125, modifiers: [.function]) else {
            return XCTFail("ArrowDown should be a navigation key")
        }
        XCTAssertEqual(chord.combo, "ArrowDown")
        XCTAssertEqual(chord.modifiers, [])
    }

    // MARK: - Toggle immunity (R3)

    func testToggleHotkeyIsConsumedNotRecorded() {
        XCTAssertEqual(makeRecognizer().evaluate(key: " ", code: 49, modifiers: [.option]), .toggleRecording(combo: "⌥Space"))
        // Settings-style string with whitespace still matches.
        XCTAssertEqual(makeRecognizer(toggleCombo: "⌥ Space").evaluate(key: " ", code: 49, modifiers: [.option]), .toggleRecording(combo: "⌥Space"))
    }

    // MARK: - System combos

    func testSystemCombosAreConsumed() {
        XCTAssertEqual(makeRecognizer().evaluate(key: "Tab", code: 48, modifiers: [.command]), .systemConsumed(combo: "⌘Tab"))
        XCTAssertEqual(makeRecognizer().evaluate(key: " ", code: 49, modifiers: [.command]), .systemConsumed(combo: "⌘Space"))
        XCTAssertEqual(makeRecognizer().evaluate(key: "Tab", code: 48, modifiers: [.command, .shift]), .systemConsumed(combo: "⌘⇧Tab"))
    }

    func testUserIgnoredCombosAreConsumed() {
        var settings = HotkeyCaptureSettings()
        settings.ignoredCombos = ["⌘⇧K"]
        XCTAssertEqual(makeRecognizer(settings: settings).evaluate(key: "K", code: 40, modifiers: [.command, .shift]), .systemConsumed(combo: "⌘⇧K"))
    }

    // MARK: - Capture settings gates

    func testModifierShortcutCaptureCanBeDisabled() {
        var settings = HotkeyCaptureSettings()
        settings.captureModifierShortcuts = false
        XCTAssertEqual(makeRecognizer(settings: settings).evaluate(key: "s", code: 1, modifiers: [.command]), .ignored)
    }

    func testControlInterruptSurvivesDisabledModifierShortcutCapture() {
        var settings = HotkeyCaptureSettings()
        settings.captureModifierShortcuts = false
        guard case let .workflowShortcut(chord) = makeRecognizer(settings: settings).evaluate(key: "c", code: 8, modifiers: [.control]) else {
            return XCTFail("⌃C must keep flowing to the engine's terminal-interrupt path")
        }
        XCTAssertEqual(chord.combo, "⌃C")
    }

    func testNavigationCaptureCanBeDisabledWithoutFallingBackToText() {
        var settings = HotkeyCaptureSettings()
        settings.captureNavigationKeys = false
        XCTAssertEqual(makeRecognizer(settings: settings).evaluate(key: "Escape", code: 53, modifiers: []), .ignored)
        // Plain typing keeps working.
        XCTAssertEqual(makeRecognizer(settings: settings).evaluate(key: "a", code: 0, modifiers: []), .textInput(key: "a", modifiers: []))
    }

    // MARK: - Text input & ignored keys

    func testPlainCharactersStayTextInput() {
        XCTAssertEqual(makeRecognizer().evaluate(key: "a", code: 0, modifiers: []), .textInput(key: "a", modifiers: []))
        XCTAssertEqual(makeRecognizer().evaluate(key: "A", code: 0, modifiers: [.shift]), .textInput(key: "A", modifiers: [.shift]))
        XCTAssertEqual(makeRecognizer().evaluate(key: " ", code: 49, modifiers: []), .textInput(key: " ", modifiers: []))
        // Option-composed characters (⌥2 → ™) must stay typed text.
        XCTAssertEqual(makeRecognizer().evaluate(key: "™", code: 19, modifiers: [.option]), .textInput(key: "™", modifiers: [.option]))
    }

    func testModifierKeysAreIgnored() {
        for keyCode: UInt16 in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] {
            let decision = makeRecognizer().evaluate(
                keyCode: keyCode,
                characters: nil,
                charactersIgnoringModifiers: nil,
                modifiers: [.shift]
            )
            XCTAssertEqual(decision, .ignored, "Modifier keyCode \(keyCode) must be ignored")
        }
    }

    // MARK: - Raw NSEvent-field decoding

    func testDriverEntryPointUsesModifierIndependentCharactersForChords() {
        // ⌘⇧S arrives as charactersIgnoringModifiers = "S" with shift flagged.
        guard case let .workflowShortcut(chord) = makeRecognizer().evaluate(
            keyCode: 1,
            characters: "s",
            charactersIgnoringModifiers: "S",
            modifiers: [.command, .shift]
        ) else {
            return XCTFail("Expected ⌘⇧S workflow shortcut")
        }
        XCTAssertEqual(chord.combo, "⌘⇧S")
    }

    func testDriverEntryPointKeepsComposedCharactersForPlainTyping() {
        // ⌥2 composes "™" — the typed character, not the "2" key, is the input.
        XCTAssertEqual(
            makeRecognizer().evaluate(keyCode: 19, characters: "™", charactersIgnoringModifiers: "2", modifiers: [.option]),
            .textInput(key: "™", modifiers: [.option])
        )
    }

    func testDriverEntryPointDecodesFunctionKeys() {
        guard case let .navigationKey(chord) = makeRecognizer().evaluate(
            keyCode: 122,
            characters: nil,
            charactersIgnoringModifiers: nil,
            modifiers: [.function]
        ) else {
            return XCTFail("F1 should be a navigation key")
        }
        XCTAssertEqual(chord.combo, "F1")
    }
}
