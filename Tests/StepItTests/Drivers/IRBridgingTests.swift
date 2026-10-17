import XCTest
import AppKit
@testable import StepItCore

final class IRBridgingTests: XCTestCase {

    // MARK: - Key code mapping table

    func testKeyCodeMappingTable() {
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 36, characters: "\r"), "Return")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 76, characters: "\r"), "Return")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 51, characters: "\u{7f}"), "Backspace")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 48, characters: "\t"), "Tab")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 49, characters: " "), " ")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 53, characters: "\u{1b}"), "Escape")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 123, characters: nil), "ArrowLeft")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 124, characters: nil), "ArrowRight")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 125, characters: nil), "ArrowDown")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 126, characters: nil), "ArrowUp")
        // Phase 2 (T2): function keys.
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 122, characters: nil), "F1")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 120, characters: nil), "F2")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 111, characters: nil), "F12")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 117, characters: nil), "Delete")
    }

    func testKeyCodeMappingPrintableFallback() {
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 0, characters: "a"), "a")
        XCTAssertEqual(KeyCodeMap.w3cKeyName(for: 1, characters: "s"), "s")
        // Non-printable control characters are not keystrokes.
        XCTAssertNil(KeyCodeMap.w3cKeyName(for: 8, characters: "\u{3}"))
        // Unmapped key codes with no characters yield nothing.
        XCTAssertNil(KeyCodeMap.w3cKeyName(for: 71, characters: nil))
        XCTAssertNil(KeyCodeMap.w3cKeyName(for: 5, characters: ""))

        // Modifier-only keys are flagged so the recognizer ignores them.
        XCTAssertTrue(KeyCodeMap.isModifierKey(55))
        XCTAssertTrue(KeyCodeMap.isModifierKey(56))
        XCTAssertFalse(KeyCodeMap.isModifierKey(36))
    }

    // MARK: - Modifier bridging

    func testModifierFlagBridging() {
        XCTAssertEqual(KeyModifiers([.option]), [.option])
        XCTAssertEqual(KeyModifiers([.command, .shift]).symbolString, "⌘⇧")
        XCTAssertEqual(KeyModifiers([.control, .function]).symbolString, "⌃fn")
        XCTAssertEqual(KeyModifiers([]), [])
    }

    // MARK: - ElementInspector → IR

    func testInspectionToIRConversion() {
        let result = ElementInspectionResult(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "GitHub",
            role: "AXButton",
            subrole: "AXStandard",
            title: "Submit Order",
            value: "go",
            roleDescription: "button",
            isSecure: false,
            elementBounds: ElementRect(x: 10, y: 20, width: 100, height: 40),
            windowBounds: ElementRect(x: 0, y: 0, width: 1200, height: 800)
        )

        let context = RawElementContext(result)

        XCTAssertEqual(context.appName, "Safari")
        XCTAssertEqual(context.bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(context.windowTitle, "GitHub")
        XCTAssertEqual(context.role, "AXButton")
        XCTAssertEqual(context.subrole, "AXStandard")
        XCTAssertEqual(context.title, "Submit Order")
        XCTAssertEqual(context.value, "go")
        XCTAssertEqual(context.roleDescription, "button")
        XCTAssertEqual(context.boundingBox, ElementRect(x: 10, y: 20, width: 100, height: 40))
        XCTAssertEqual(context.windowBounds, ElementRect(x: 0, y: 0, width: 1200, height: 800))

        // Phase 1 emits accessibility + coordinates selectors, AX preferred.
        XCTAssertEqual(context.selectors.map(\.kind), [.accessibility, .coordinates])
        XCTAssertEqual(context.selectors[0].priority, 0)
        XCTAssertFalse(context.selectors[0].value.isEmpty)
    }

    func testInspectionSecureFlagTravelsTheIR() {
        let secure = ElementInspectionResult(
            appName: "Safari",
            role: "AXTextField",
            subrole: "AXSecureTextField",
            isSecure: true
        )
        XCTAssertTrue(RawElementContext(secure).isSecure)

        XCTAssertTrue(AccessibilityInspector.isSecureField(role: "AXSecureTextField", subrole: nil))
        XCTAssertTrue(AccessibilityInspector.isSecureField(role: nil, subrole: "AXSecureTextField"))
        XCTAssertFalse(AccessibilityInspector.isSecureField(role: "AXTextField", subrole: nil))
    }

    func testInspectionWithoutElementBoundsHasCoordinatesOmitted() {
        let result = ElementInspectionResult(appName: "Finder", role: "AXWindow")
        let context = RawElementContext(result)
        XCTAssertEqual(context.selectors.map(\.kind), [.accessibility])
    }

    // MARK: - Geometry bridging

    func testPointAndRectBridging() {
        let point = Point2D(CGPoint(x: 12.5, y: 44.25))
        XCTAssertEqual(point, Point2D(x: 12.5, y: 44.25))
        XCTAssertEqual(CGPoint(point), CGPoint(x: 12.5, y: 44.25))

        let rect = ElementRect(CGRect(x: 1, y: 2, width: 30, height: 40))
        XCTAssertEqual(rect, ElementRect(x: 1, y: 2, width: 30, height: 40))
    }

    // MARK: - Gesture bridging

    func testGestureNoticeToRawInputEvent() {
        let notice = GestureEventNotice(
            action: .stopAndReview,
            gestureName: "Mouse Shake 🔀 (620 px/s)",
            timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            location: CGPoint(x: 300, y: 400)
        )

        let event = RawInputEvent.userGesture(notice)

        XCTAssertEqual(event.kind, .userGesture(name: "Mouse Shake 🔀 (620 px/s)", action: .stopAndReview))
        XCTAssertEqual(event.location, Point2D(x: 300, y: 400))
        XCTAssertEqual(event.timestamp, notice.timestamp)
    }
}
