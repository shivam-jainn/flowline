import XCTest
import FlowlineIR
import FlowlineAIGateway

final class AIMentionsTests: XCTestCase {
    private func makeSession() -> StepSession {
        StepSession(
            title: "Demo",
            steps: [
                Step(index: 1, action: .click, appName: "Safari", windowTitle: "Home", actionDescription: "Open Safari home"),
                Step(index: 2, action: .typing, appName: "Terminal", windowTitle: "zsh", actionDescription: "Type git status in Terminal"),
                Step(index: 3, action: .click, appName: "Xcode", windowTitle: "Build", actionDescription: "Press Run in Xcode"),
            ]
        )
    }

    func testActiveQueryDetectsTrailingMention() {
        XCTAssertNil(AIMentions.activeQuery(in: "hello"))
        XCTAssertEqual(AIMentions.activeQuery(in: "fix @")?.query, "")
        XCTAssertEqual(AIMentions.activeQuery(in: "fix @st")?.query, "st")
        XCTAssertEqual(AIMentions.activeQuery(in: "fix @step-2")?.query, "step-2")
        // Finished token + space hides the picker.
        XCTAssertNil(AIMentions.activeQuery(in: "fix @step-2 "))
        XCTAssertNil(AIMentions.activeQuery(in: "fix @step-2 please"))
        // Emails are not mentions.
        XCTAssertNil(AIMentions.activeQuery(in: "mail me@home"))
        // Punctuation ends the token.
        XCTAssertNil(AIMentions.activeQuery(in: "fix @step,"))
    }

    func testOptionsListsCurrentSteps() {
        let session = makeSession()
        let all = AIMentions.options(session: session, scopeStep: session.steps[0], query: "")
        // guide + selected + recording + automation + 3 steps
        XCTAssertEqual(all.count, 7)
        XCTAssertTrue(all.contains(where: { $0.token == "@step-1" && $0.title == "Step 1" }))
        XCTAssertTrue(all.contains(where: { $0.token == "@step-2" }))
        XCTAssertTrue(all.contains(where: { $0.token == "@step-3" }))
    }

    func testOptionsFiltersByNumberAndText() {
        let session = makeSession()
        let byNumber = AIMentions.options(session: session, scopeStep: nil, query: "2")
        XCTAssertTrue(byNumber.contains(where: { $0.token == "@step-2" }))
        XCTAssertFalse(byNumber.contains(where: { $0.token == "@step-1" }))

        let byText = AIMentions.options(session: session, scopeStep: nil, query: "xcode")
        XCTAssertTrue(byText.contains(where: { $0.token == "@step-3" }))

        let guides = AIMentions.options(session: session, scopeStep: nil, query: "gui")
        XCTAssertTrue(guides.contains(where: { $0.token == "@guide" }))
    }

    func testApplyingReplacesActiveQuery() {
        let session = makeSession()
        let opt = AIMentions.options(session: session, scopeStep: nil, query: "").first(where: { $0.token == "@step-2" })!
        XCTAssertEqual(AIMentions.applying(option: opt, to: "summarize @st"), "summarize @step-2 ")
        XCTAssertEqual(AIMentions.applying(option: opt, to: "summarize"), "summarize @step-2 ")
    }

    func testScopedSessionPrefersExplicitSteps() {
        let session = makeSession()
        let scoped = AIMentions.scopedSession(session: session, scopeStep: session.steps[0], instructions: "explain @step-2 and @step-3")
        XCTAssertEqual(scoped.steps.map(\.index), [2, 3])

        let dashless = AIMentions.scopedSession(session: session, scopeStep: nil, instructions: "fix @step2")
        XCTAssertEqual(dashless.steps.map(\.index), [2])

        let bare = AIMentions.scopedSession(session: session, scopeStep: session.steps[2], instructions: "rewrite @step please")
        XCTAssertEqual(bare.steps.map(\.index), [3])

        let full = AIMentions.scopedSession(session: session, scopeStep: session.steps[0], instructions: "summarize @guide")
        XCTAssertEqual(full.steps.count, 3)
    }
}
