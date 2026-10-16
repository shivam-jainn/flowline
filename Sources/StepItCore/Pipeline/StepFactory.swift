import Foundation

/// Single place where IR → `Step` mapping happens.
///
/// Locks in behavior parity with the pre-Phase-1 coordinator:
/// click steps keep the `ActionType` mapping (`clickCount >= 2 → .doubleClick`,
/// right → `.rightClick`) and rely on `Step.synthesizeDefaultDescription`;
/// typing steps reproduce the three description branches, role tags and
/// `isCode`/`codeLanguage` fields byte-for-byte.
public enum StepFactory {

    // MARK: - Clicks

    public static func actionType(for button: MouseButton, clickCount: Int) -> ActionType {
        if button == .right {
            return .rightClick
        }
        if clickCount >= 2 {
            return .doubleClick
        }
        return .click
    }

    public static func makeClickStep(
        index: Int,
        event: RawInputEvent,
        context: RawElementContext?,
        assets: MediaAssets
    ) -> Step {
        let action: ActionType
        if case let .mouseClick(button, clickCount) = event.kind {
            action = actionType(for: button, clickCount: clickCount)
        } else {
            action = .manual
        }
        return makeClickStep(
            index: index,
            timestamp: event.timestamp,
            action: action,
            location: event.location ?? .zero,
            context: context,
            assets: assets
        )
    }

    public static func makeClickStep(
        index: Int,
        timestamp: Date,
        action: ActionType,
        location: Point2D,
        context: RawElementContext?,
        assets: MediaAssets
    ) -> Step {
        let context = context ?? .unknown
        return Step(
            index: index,
            timestamp: timestamp,
            action: action,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            elementRole: context.role,
            elementTitle: context.title,
            elementValue: context.value,
            coordinates: ScreenCoordinates(x: location.x, y: location.y),
            windowBounds: context.windowBounds,
            elementBounds: context.boundingBox,
            assets: assets
        )
    }

    // MARK: - Typing / commands

    public static func makeTypingStep(
        index: Int,
        timestamp: Date,
        result: TypingBatchResult,
        assets: MediaAssets
    ) -> Step {
        let context = result.context ?? .unknown
        let cleanText = result.textBlob.trimmingCharacters(in: .whitespacesAndNewlines)

        let action: ActionType
        let description: String
        let role: String
        let langTag: String?

        switch result.classification {
        case .terminal:
            action = .writeCode
            description = "Run \"\(cleanText)\" in \(context.appName)"
            role = "AXTerminal"
            langTag = "bash"
        case .code(let language):
            action = .writeCode
            description = "Write code in \(context.appName)"
            role = "AXCodeEditor"
            langTag = language
        case .text:
            action = .typing
            let preview = cleanText.prefix(32)
            description = "Type \"\(preview)\(cleanText.count > 32 ? "..." : "")\" in \(context.appName)"
            role = "AXTextField"
            langTag = nil
        }

        return Step(
            index: index,
            timestamp: timestamp,
            action: action,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            elementRole: role,
            elementTitle: langTag.map { "(\($0))" },
            coordinates: ScreenCoordinates(x: result.location.x, y: result.location.y),
            actionDescription: description,
            textBlob: result.textBlob,
            isCode: action == .writeCode,
            codeLanguage: langTag,
            assets: assets
        )
    }

    // MARK: - Manual steps

    public static func makeManualStep(
        index: Int,
        timestamp: Date = Date(),
        title: String,
        notes: String? = nil
    ) -> Step {
        Step(
            index: index,
            timestamp: timestamp,
            action: .manual,
            appName: "Manual Action",
            windowTitle: "",
            actionDescription: title,
            userNotes: notes
        )
    }
}
