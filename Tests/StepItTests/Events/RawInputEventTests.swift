import XCTest
import StepItIR
import StepItPipeline
@testable import StepItCore

final class RawInputEventTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Codable round-trips (Phase 4 serializes event streams for free)

    func testRoundTripAllEmittedKinds() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 800_000_000.25)

        let events: [RawInputEvent] = [
            RawInputEvent(
                timestamp: timestamp,
                kind: .mouseClick(button: .left, clickCount: 2),
                location: Point2D(x: 12.5, y: 44.25),
                targetContext: RawEventFixtures.ctx(
                    app: "Safari",
                    windowTitle: "GitHub",
                    role: "AXButton",
                    title: "Submit",
                    isSecure: false,
                    bounds: ElementRect(x: 1, y: 2, width: 3, height: 4)
                )
            ),
            RawInputEvent(
                timestamp: timestamp,
                kind: .keyStroke(key: "Return", code: 36, modifiers: [.shift]),
                location: Point2D(x: 0, y: 0)
            ),
            RawInputEvent(timestamp: timestamp, kind: .hotkeyCombo(combo: "⌥Space")),
            RawInputEvent(
                timestamp: timestamp,
                kind: .userGesture(name: "Mouse Shake 🔀", action: .pauseResume),
                location: Point2D(x: 5, y: 6)
            )
        ]

        for event in events {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(RawInputEvent.self, from: data)
            XCTAssertEqual(decoded, event)
        }
    }

    func testRoundTripReservedKinds() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 800_000_100.5)

        let reserved: [RawInputEvent.Kind] = [
            .mouseDrag(start: Point2D(x: 1, y: 2), end: Point2D(x: 3, y: 4)),
            .appSwitch(bundleId: "com.apple.Safari", appName: "Safari", windowTitle: "Docs"),
            .terminalCommand(command: "ls -la", workingDir: "/tmp", exitCode: 0),
            .pageNavigation(url: "https://example.com", title: "Example")
        ]

        for kind in reserved {
            let event = RawInputEvent(timestamp: timestamp, kind: kind, location: Point2D(x: 7, y: 8))
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(RawInputEvent.self, from: data)
            XCTAssertEqual(decoded.kind, kind)
            XCTAssertEqual(decoded, event)
        }
    }

    // MARK: - Modifier + button vocabulary

    func testKeyModifiersSymbolString() {
        XCTAssertEqual(KeyModifiers.option.symbolString, "⌥")
        XCTAssertEqual(KeyModifiers.command.symbolString, "⌘")
        XCTAssertEqual(KeyModifiers([.command, .option, .control, .shift]).symbolString, "⌘⌥⌃⇧")
        XCTAssertEqual(KeyModifiers([.command, .function]).symbolString, "⌘fn")
        XCTAssertEqual(KeyModifiers([]).symbolString, "")

        // The hotkey route the HUD/menu advertises.
        let combo = KeyModifiers.option.symbolString + "Space"
        XCTAssertEqual(combo, "⌥Space")
    }

    // MARK: - Phase 2: HotkeyChord rendering

    func testHotkeyChordComboRendering() {
        XCTAssertEqual(HotkeyChord(key: "s", code: 1, modifiers: [.command]).combo, "⌘S")
        XCTAssertEqual(HotkeyChord(key: "P", code: 35, modifiers: [.command, .shift]).combo, "⌘⇧P")
        XCTAssertEqual(HotkeyChord(key: " ", code: 49, modifiers: [.option]).combo, "⌥Space")
        XCTAssertEqual(HotkeyChord(key: "Escape", code: 53).combo, "Escape")
        XCTAssertEqual(HotkeyChord(key: "ArrowDown", code: 125).combo, "ArrowDown")

        XCTAssertFalse(HotkeyChord(key: "Escape").isShortcut)
        XCTAssertTrue(HotkeyChord(key: "s", modifiers: [.command]).isShortcut)
    }

    func testHotkeyChordRoundTrip() throws {
        let chord = HotkeyChord(key: "p", displayKey: "P", code: 35, modifiers: [.command, .shift])
        let decoded = try decoder.decode(HotkeyChord.self, from: try encoder.encode(chord))
        XCTAssertEqual(decoded, chord)
    }

    // MARK: - Phase 2: Step schema additions

    func testStepPhaseTwoFieldsRoundTrip() throws {
        let step = Step(
            index: 7,
            action: .keyPress,
            appName: "Ghostty",
            actionDescription: "Press ⌘S to save in Ghostty",
            assets: MediaAssets(screenshot: "media/step_07.png", screenshotOriginal: "media/step_07.original.png"),
            workingDirectory: "~/Code/stepit",
            hotkeyCombo: "⌘S",
            isRedacted: true
        )

        let decoded = try decoder.decode(Step.self, from: try encoder.encode(step))
        XCTAssertEqual(decoded, step)
        XCTAssertEqual(decoded.workingDirectory, "~/Code/stepit")
        XCTAssertEqual(decoded.hotkeyCombo, "⌘S")
        XCTAssertEqual(decoded.isRedacted, true)
        XCTAssertEqual(decoded.assets.screenshotOriginal, "media/step_07.original.png")
    }

    func testPhase1StepJSONDecodesWithNilPhaseTwoFields() throws {
        // A Phase 1 step.json without any Phase 2 keys must keep loading (DoD #7).
        let legacy = """
        {
          "id": "legacy",
          "index": 1,
          "timestamp": 800000000,
          "action": "click",
          "appName": "Safari",
          "windowTitle": "GitHub",
          "actionDescription": "Click \\"Submit\\" in GitHub",
          "isCode": false,
          "assets": { "screenshot": "media/step_01.png" }
        }
        """

        let decoded = try decoder.decode(Step.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.actionDescription, "Click \"Submit\" in GitHub")
        XCTAssertNil(decoded.workingDirectory)
        XCTAssertNil(decoded.hotkeyCombo)
        XCTAssertNil(decoded.isRedacted)
        XCTAssertNil(decoded.assets.screenshotOriginal)
    }

    func testMouseDragActionRawValue() {
        XCTAssertEqual(ActionType.mouseDrag.rawValue, "mouse_drag")
    }

    func testMouseButtonNumberMapping() {
        XCTAssertEqual(MouseButton(buttonNumber: 0), .left)
        XCTAssertEqual(MouseButton(buttonNumber: 1), .right)
        XCTAssertEqual(MouseButton(buttonNumber: 2), .middle)
        XCTAssertNil(MouseButton(buttonNumber: 3))
        XCTAssertNil(MouseButton(buttonNumber: 7))
    }

    func testUnknownContextPlaceholder() {
        XCTAssertEqual(RawElementContext.unknown.appName, "Unknown App")
        XCTAssertTrue(RawElementContext.unknown.selectors.isEmpty)
        XCTAssertFalse(RawElementContext.unknown.isSecure)
    }

    func testElementSelectorPriorityOrdering() {
        let selectors = [
            ElementSelector(kind: .accessibility, value: "role=\"AXButton\"", priority: 0),
            ElementSelector(kind: .coordinates, value: "10,20", priority: 1)
        ]
        XCTAssertEqual(selectors.sorted { $0.priority < $1.priority }.map(\.kind), [.accessibility, .coordinates])
    }

    // MARK: - Artifacts

    func testCaptureArtifactsRoundTrip() throws {
        let snapshot = FrameSnapshot(pngData: MockAssets.onePixelPNG, scale: 2.0)
        let clip = ClipAsset(gifData: MockAssets.gifStub, videoData: MockAssets.mp4Stub, duration: 0.6)
        let config = ClipBufferConfig(fps: 15, maxBufferSeconds: 0.5)

        XCTAssertEqual(try decoder.decode(FrameSnapshot.self, from: try encoder.encode(snapshot)), snapshot)
        XCTAssertEqual(try decoder.decode(ClipAsset.self, from: try encoder.encode(clip)), clip)
        XCTAssertEqual(try decoder.decode(ClipBufferConfig.self, from: try encoder.encode(config)), config)
    }

    func testMockOnePixelPNGIsAValidPNG() {
        // PNG magic bytes + IEND marker.
        let bytes = [UInt8](MockAssets.onePixelPNG)
        XCTAssertEqual(Array(bytes.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertGreaterThan(bytes.count, 50)
    }
}
