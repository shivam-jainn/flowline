import Foundation

/// Single place where IR → `Step` mapping happens.
///
/// Locks in behavior parity with the pre-Phase-1 coordinator:
/// click steps keep the `ActionType` mapping (`clickCount >= 2 → .doubleClick`,
/// right → `.rightClick`) and rely on `Step.synthesizeDefaultDescription`;
/// typing steps reproduce the three description branches, role tags and
/// `isCode`/`codeLanguage` fields byte-for-byte.
///
/// Phase 2 adds dedicated factories for discrete key presses (T3), terminal
/// commands with `pwd` (T5), mouse drags and app switches (T8).
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
        assets: MediaAssets,
        isRedacted: Bool? = nil
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
            elementValue: context.isSecure ? nil : context.value,
            coordinates: ScreenCoordinates(x: location.x, y: location.y),
            windowBounds: context.windowBounds,
            elementBounds: context.boundingBox,
            assets: assets,
            isRedacted: isRedacted
        )
    }

    // MARK: - Typing / commands

    public static func makeTypingStep(
        index: Int,
        timestamp: Date,
        result: TypingBatchResult,
        assets: MediaAssets,
        workingDirectory: String? = nil,
        isRedacted: Bool? = nil
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
            description = terminalCommandDescription(
                command: cleanText,
                workingDirectory: workingDirectory,
                appName: context.appName
            )
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
            assets: assets,
            workingDirectory: result.classification == .terminal ? workingDirectory : nil,
            isRedacted: isRedacted
        )
    }

    /// Step for a directly-emitted `.terminalCommand` IR event (T5).
    public static func makeTerminalCommandStep(
        index: Int,
        timestamp: Date,
        command: String,
        workingDirectory: String?,
        context: RawElementContext?,
        assets: MediaAssets,
        isRedacted: Bool? = nil
    ) -> Step {
        let context = context ?? .unknown
        let cleanText = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return Step(
            index: index,
            timestamp: timestamp,
            action: .writeCode,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            elementRole: "AXTerminal",
            elementTitle: "(bash)",
            coordinates: context.windowBounds.map { ScreenCoordinates(x: $0.center.x, y: $0.center.y) },
            actionDescription: terminalCommandDescription(
                command: cleanText,
                workingDirectory: workingDirectory,
                appName: context.appName
            ),
            textBlob: command,
            isCode: true,
            codeLanguage: "bash",
            assets: assets,
            workingDirectory: workingDirectory,
            isRedacted: isRedacted
        )
    }

    /// `Run "git status" in ~/Code/stepit (Ghostty)` when the `pwd` is known;
    /// legacy `Run "git status" in Ghostty` otherwise (E2).
    static func terminalCommandDescription(command: String, workingDirectory: String?, appName: String) -> String {
        if let directory = workingDirectory, !directory.isEmpty {
            return "Run \"\(command)\" in \(directory) (\(appName))"
        }
        return "Run \"\(command)\" in \(appName)"
    }

    // MARK: - Discrete key presses (T2/T3)

    public static func makeKeyPressStep(
        index: Int,
        timestamp: Date,
        chord: HotkeyChord,
        context: RawElementContext?,
        assets: MediaAssets = MediaAssets(),
        isRedacted: Bool? = nil
    ) -> Step {
        let context = context ?? .unknown
        let combo = chord.combo
        let appName = context.appName.isEmpty ? RawElementContext.unknown.appName : context.appName

        let description: String
        if combo == "⌘S" {
            description = "Press ⌘S to save in \(appName)"
        } else {
            description = "Press \(combo) in \(appName)"
        }

        return Step(
            index: index,
            timestamp: timestamp,
            action: .keyPress,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            elementRole: "AXKeyboard",
            elementTitle: chord.key,
            coordinates: context.boundingBox.map { ScreenCoordinates(x: $0.center.x, y: $0.center.y) },
            windowBounds: context.windowBounds,
            elementBounds: context.boundingBox,
            actionDescription: description,
            assets: assets,
            hotkeyCombo: chord.isShortcut ? combo : nil,
            isRedacted: isRedacted
        )
    }

    // MARK: - Mouse drags (T8)

    public static func makeDragStep(
        index: Int,
        timestamp: Date,
        start: Point2D,
        end: Point2D,
        context: RawElementContext?,
        assets: MediaAssets,
        isRedacted: Bool? = nil
    ) -> Step {
        let context = context ?? .unknown
        let description = "Drag from (\(Int(start.x.rounded())), \(Int(start.y.rounded()))) "
            + "to (\(Int(end.x.rounded())), \(Int(end.y.rounded()))) in \(context.appName)"

        return Step(
            index: index,
            timestamp: timestamp,
            action: .mouseDrag,
            appName: context.appName,
            bundleIdentifier: context.bundleIdentifier,
            windowTitle: context.windowTitle,
            elementRole: "AXDrag",
            coordinates: ScreenCoordinates(x: end.x, y: end.y),
            windowBounds: context.windowBounds,
            elementBounds: context.boundingBox,
            actionDescription: description,
            assets: assets,
            isRedacted: isRedacted
        )
    }

    // MARK: - App switches (T8)

    public static func makeAppSwitchStep(
        index: Int,
        timestamp: Date,
        bundleId: String?,
        appName: String,
        windowTitle: String
    ) -> Step {
        Step(
            index: index,
            timestamp: timestamp,
            action: .appSwitch,
            appName: appName,
            bundleIdentifier: bundleId,
            windowTitle: windowTitle,
            actionDescription: "Switch to \(appName)"
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
