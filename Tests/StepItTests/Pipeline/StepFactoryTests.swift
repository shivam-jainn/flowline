import XCTest
import StepItIR
import StepItPipeline
import AppKit
@testable import StepItCore

final class StepFactoryTests: XCTestCase {

    // MARK: - Click steps (golden descriptions)

    func testClickDescriptionParity() {
        let context = RawEventFixtures.ctx(
            app: "CheckoutApp",
            windowTitle: "Cart Summary",
            role: "AXButton",
            title: "Submit Order"
        )
        let event = RawEventFixtures.click(
            at: Point2D(x: 420, y: 310),
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            context: context
        )

        let step = StepFactory.makeClickStep(index: 1, event: event, context: context, assets: MediaAssets(screenshot: "media/step_01.png"))

        XCTAssertEqual(step.actionDescription, "Click \"Submit Order\" in Cart Summary")
        XCTAssertEqual(step.action, .click)
        XCTAssertEqual(step.appName, "CheckoutApp")
        XCTAssertEqual(step.windowTitle, "Cart Summary")
        XCTAssertEqual(step.elementRole, "AXButton")
        XCTAssertEqual(step.elementTitle, "Submit Order")
        XCTAssertEqual(step.coordinates, ScreenCoordinates(x: 420, y: 310))
        XCTAssertEqual(step.assets.screenshot, "media/step_01.png")
    }

    func testRightClickAndDoubleClickMapping() {
        XCTAssertEqual(StepFactory.actionType(for: .right, clickCount: 1), .rightClick)
        XCTAssertEqual(StepFactory.actionType(for: .right, clickCount: 2), .rightClick)
        XCTAssertEqual(StepFactory.actionType(for: .left, clickCount: 1), .click)
        XCTAssertEqual(StepFactory.actionType(for: .left, clickCount: 2), .doubleClick)

        let rightContext = RawEventFixtures.ctx(app: "Finder", bundleId: "com.apple.finder", windowTitle: "", role: "AXMenuItem")
        let rightStep = StepFactory.makeClickStep(
            index: 2,
            timestamp: Date(),
            action: .rightClick,
            location: .zero,
            context: rightContext,
            assets: MediaAssets()
        )
        XCTAssertEqual(rightStep.actionDescription, "Right-click menuitem in Finder")

        let doubleContext = RawEventFixtures.ctx(app: "Notes", windowTitle: "Draft", role: "AXTextField", title: "Title")
        let doubleStep = StepFactory.makeClickStep(
            index: 3,
            timestamp: Date(),
            action: .doubleClick,
            location: .zero,
            context: doubleContext,
            assets: MediaAssets()
        )
        XCTAssertEqual(doubleStep.actionDescription, "Double-click \"Title\" in Draft")
    }

    func testClickStepWithoutContextFallsBackToUnknownPlaceholder() {
        let step = StepFactory.makeClickStep(
            index: 1,
            timestamp: Date(),
            action: .click,
            location: .zero,
            context: nil,
            assets: MediaAssets()
        )
        XCTAssertEqual(step.appName, "Unknown App")
    }

    func testManualSnapshotActionKeepsManualDescription() {
        let context = RawEventFixtures.ctx(app: "System Settings", windowTitle: "Privacy & Security", role: "AXButton", title: "Advanced...")
        let step = StepFactory.makeClickStep(
            index: 4,
            timestamp: Date(),
            action: .manual,
            location: Point2D(x: 10, y: 10),
            context: context,
            assets: MediaAssets()
        )
        XCTAssertEqual(step.action, .manual)
        XCTAssertEqual(step.actionDescription, "Perform step in \"Advanced...\" in Privacy & Security")
    }

    // MARK: - Typing steps (golden descriptions)

    func testTerminalTypingDescriptionParity() {
        let context = RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty", windowTitle: "ghostty")
        let result = TypingBatchResult(
            textBlob: "git status",
            context: context,
            classification: .terminal,
            location: Point2D(x: 50, y: 60)
        )

        let step = StepFactory.makeTypingStep(index: 1, timestamp: Date(), result: result, assets: MediaAssets(screenshot: "media/step_01.png"))

        XCTAssertEqual(step.actionDescription, "Run \"git status\" in Ghostty")
        XCTAssertEqual(step.action, .writeCode)
        XCTAssertEqual(step.elementRole, "AXTerminal")
        XCTAssertEqual(step.elementTitle, "(bash)")
        XCTAssertEqual(step.codeLanguage, "bash")
        XCTAssertTrue(step.isCode)
        XCTAssertEqual(step.textBlob, "git status")
        XCTAssertEqual(step.coordinates, ScreenCoordinates(x: 50, y: 60))
    }

    func testRunNpmFamilyDescriptionParity() {
        let context = RawEventFixtures.ctx(app: "Warp", bundleId: "dev.warp.Warp-Stable")
        let result = TypingBatchResult(textBlob: "npm run build", context: context, classification: .terminal, location: .zero)
        let step = StepFactory.makeTypingStep(index: 2, timestamp: Date(), result: result, assets: MediaAssets())
        XCTAssertEqual(step.actionDescription, "Run \"npm run build\" in Warp")
        XCTAssertEqual(step.codeLanguage, "bash")
    }

    func testCodeTypingDescriptionParity() {
        let context = RawEventFixtures.ctx(app: "Visual Studio Code", bundleId: "com.microsoft.VSCode", windowTitle: "main.swift")
        let result = TypingBatchResult(
            textBlob: "let x = 1",
            context: context,
            classification: .code(language: "swift"),
            location: .zero
        )

        let step = StepFactory.makeTypingStep(index: 1, timestamp: Date(), result: result, assets: MediaAssets())

        XCTAssertEqual(step.actionDescription, "Write code in Visual Studio Code")
        XCTAssertEqual(step.action, .writeCode)
        XCTAssertEqual(step.elementRole, "AXCodeEditor")
        XCTAssertEqual(step.elementTitle, "(swift)")
        XCTAssertEqual(step.codeLanguage, "swift")
        XCTAssertTrue(step.isCode)
    }

    func testPlainTextTypingDescriptionParity() {
        let context = RawEventFixtures.ctx(app: "Notes", windowTitle: "Draft", role: "AXTextField")
        let result = TypingBatchResult(
            textBlob: "Hello team, here is a longer note that exceeds 32 characters",
            context: context,
            classification: .text,
            location: .zero
        )

        let step = StepFactory.makeTypingStep(index: 1, timestamp: Date(), result: result, assets: MediaAssets())

        XCTAssertEqual(step.action, .typing)
        XCTAssertEqual(step.elementRole, "AXTextField")
        XCTAssertNil(step.elementTitle)
        XCTAssertNil(step.codeLanguage)
        XCTAssertFalse(step.isCode)
        // 32-character preview + ellipsis.
        XCTAssertEqual(step.actionDescription, "Type \"Hello team, here is a longer not...\" in Notes")
    }

    func testShortTextTypingDescriptionHasNoEllipsis() {
        let context = RawEventFixtures.ctx(app: "Notes", windowTitle: "Draft")
        let result = TypingBatchResult(textBlob: "hi", context: context, classification: .text, location: .zero)
        let step = StepFactory.makeTypingStep(index: 1, timestamp: Date(), result: result, assets: MediaAssets())
        XCTAssertEqual(step.actionDescription, "Type \"hi\" in Notes")
    }

    func testTypingStepTrimsWhitespaceForTheDescriptionButKeepsTheBlob() {
        let context = RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty")
        let result = TypingBatchResult(textBlob: "  ls -la  ", context: context, classification: .terminal, location: .zero)
        let step = StepFactory.makeTypingStep(index: 1, timestamp: Date(), result: result, assets: MediaAssets())
        XCTAssertEqual(step.actionDescription, "Run \"ls -la\" in Ghostty")
        XCTAssertEqual(step.textBlob, "  ls -la  ")
    }

    // MARK: - Manual steps

    func testManualStepParity() {
        let step = StepFactory.makeManualStep(index: 5, title: "Deploy to production", notes: "Coordinate with SRE")

        XCTAssertEqual(step.index, 5)
        XCTAssertEqual(step.action, .manual)
        XCTAssertEqual(step.appName, "Manual Action")
        XCTAssertEqual(step.windowTitle, "")
        XCTAssertEqual(step.actionDescription, "Deploy to production")
        XCTAssertEqual(step.userNotes, "Coordinate with SRE")
    }

    // MARK: - Key press steps (Phase 2, T3 goldens)

    func testCommandSaveKeyPressGolden() {
        let context = RawEventFixtures.ctx(app: "Visual Studio Code", bundleId: "com.microsoft.VSCode")
        let step = StepFactory.makeKeyPressStep(
            index: 1,
            timestamp: Date(),
            chord: HotkeyChord(key: "s", code: 1, modifiers: [.command]),
            context: context,
            assets: MediaAssets(screenshot: "media/step_01.png")
        )

        XCTAssertEqual(step.action, .keyPress)
        XCTAssertEqual(step.actionDescription, "Press ⌘S to save in Visual Studio Code")
        XCTAssertEqual(step.hotkeyCombo, "⌘S")
        XCTAssertEqual(step.appName, "Visual Studio Code")
        XCTAssertEqual(step.assets.screenshot, "media/step_01.png")
    }

    func testCommandShiftPKeyPressGolden() {
        let context = RawEventFixtures.ctx(app: "Visual Studio Code")
        let step = StepFactory.makeKeyPressStep(
            index: 2,
            timestamp: Date(),
            chord: HotkeyChord(key: "P", code: 35, modifiers: [.command, .shift]),
            context: context
        )
        XCTAssertEqual(step.actionDescription, "Press ⌘⇧P in Visual Studio Code")
        XCTAssertEqual(step.hotkeyCombo, "⌘⇧P")
    }

    func testNavigationKeyPressGoldens() {
        let notes = RawEventFixtures.ctx(app: "Notes")
        let escape = StepFactory.makeKeyPressStep(index: 1, timestamp: Date(), chord: HotkeyChord(key: "Escape", code: 53), context: notes)
        XCTAssertEqual(escape.actionDescription, "Press Escape in Notes")
        XCTAssertNil(escape.hotkeyCombo)

        let tab = StepFactory.makeKeyPressStep(
            index: 2,
            timestamp: Date(),
            chord: HotkeyChord(key: "Tab", code: 48),
            context: RawEventFixtures.ctx(app: "Ghostty")
        )
        XCTAssertEqual(tab.actionDescription, "Press Tab in Ghostty")

        let arrow = StepFactory.makeKeyPressStep(
            index: 3,
            timestamp: Date(),
            chord: HotkeyChord(key: "ArrowDown", code: 125),
            context: notes
        )
        XCTAssertEqual(arrow.actionDescription, "Press ArrowDown in Notes")
    }

    // MARK: - Terminal working directory (Phase 2, T4/T5)

    func testTerminalTypingDescriptionCarriesPwd() {
        let context = RawEventFixtures.ctx(app: "Ghostty", bundleId: "com.mitchellh.ghostty", windowTitle: "user@host: ~/Code/stepit")
        let result = TypingBatchResult(
            textBlob: "git status",
            context: context,
            classification: .terminal,
            location: .zero
        )

        let step = StepFactory.makeTypingStep(
            index: 1,
            timestamp: Date(),
            result: result,
            assets: MediaAssets(),
            workingDirectory: "~/Code/stepit"
        )

        XCTAssertEqual(step.actionDescription, "Run \"git status\" in ~/Code/stepit (Ghostty)")
        XCTAssertEqual(step.workingDirectory, "~/Code/stepit")
        XCTAssertTrue(step.isCode)
        XCTAssertEqual(step.codeLanguage, "bash")
    }

    func testNonTerminalTypingIgnoresWorkingDirectory() {
        let context = RawEventFixtures.ctx(app: "Notes", role: "AXTextField")
        let result = TypingBatchResult(textBlob: "hi", context: context, classification: .text, location: .zero)

        let step = StepFactory.makeTypingStep(
            index: 1,
            timestamp: Date(),
            result: result,
            assets: MediaAssets(),
            workingDirectory: "~/Code/stepit"
        )
        XCTAssertNil(step.workingDirectory)
        XCTAssertEqual(step.actionDescription, "Type \"hi\" in Notes")
    }

    func testTerminalCommandFactoryGolden() {
        let context = RawEventFixtures.ctx(app: "Ghostty", windowTitle: "zsh")
        let step = StepFactory.makeTerminalCommandStep(
            index: 3,
            timestamp: Date(),
            command: "npm start",
            workingDirectory: "~/api",
            context: context,
            assets: MediaAssets()
        )

        XCTAssertEqual(step.action, .writeCode)
        XCTAssertEqual(step.actionDescription, "Run \"npm start\" in ~/api (Ghostty)")
        XCTAssertEqual(step.workingDirectory, "~/api")
        XCTAssertEqual(step.elementRole, "AXTerminal")
        XCTAssertEqual(step.codeLanguage, "bash")
    }

    // MARK: - Drag & app switch steps (Phase 2, T8)

    func testDragStepGolden() {
        let context = RawEventFixtures.ctx(app: "Finder", bundleId: "com.apple.finder")
        let step = StepFactory.makeDragStep(
            index: 4,
            timestamp: Date(),
            start: Point2D(x: 10, y: 10),
            end: Point2D(x: 300.4, y: 200.6),
            context: context,
            assets: MediaAssets(screenshot: "media/step_04.png")
        )

        XCTAssertEqual(step.action, .mouseDrag)
        XCTAssertEqual(step.actionDescription, "Drag from (10, 10) to (300, 201) in Finder")
        XCTAssertEqual(step.coordinates, ScreenCoordinates(x: 300.4, y: 200.6))
    }

    func testAppSwitchStepGolden() {
        let step = StepFactory.makeAppSwitchStep(
            index: 1,
            timestamp: Date(),
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            windowTitle: ""
        )

        XCTAssertEqual(step.action, .appSwitch)
        XCTAssertEqual(step.actionDescription, "Switch to Slack")
        XCTAssertEqual(step.bundleIdentifier, "com.tinyspeck.slackmacgap")
    }

    // MARK: - Notification parity (synthesized by Step, frozen here)

    func testNotificationDescriptionParity() {
        let context = RawEventFixtures.ctx(app: "UserNotificationCenter", windowTitle: "", role: "AXNotificationCenter", title: "Claude Code Prototype")
        let step = StepFactory.makeClickStep(
            index: 1,
            timestamp: Date(),
            action: .click,
            location: .zero,
            context: context,
            assets: MediaAssets()
        )
        XCTAssertEqual(step.actionDescription, "Click notification \"Claude Code Prototype\"")

        let empty = RawEventFixtures.ctx(app: "UserNotificationCenter", role: "AXDialog")
        let emptyStep = StepFactory.makeClickStep(
            index: 2,
            timestamp: Date(),
            action: .click,
            location: .zero,
            context: empty,
            assets: MediaAssets()
        )
        XCTAssertEqual(emptyStep.actionDescription, "Click system notification")
    }
}
