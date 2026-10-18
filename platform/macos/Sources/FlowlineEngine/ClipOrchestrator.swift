import Foundation
import FlowlineCaptureAPI
import FlowlineIR
import FlowlinePipeline

// MARK: - Clip and gesture orchestration (clip half) (R/M1-03 reducer split; verbatim logic from RecorderWorkflowEngine)

extension RecorderWorkflowEngine {
    /// Capture → secure-field blackout → offline OCR redaction → persist.
    /// Shared by every step kind so privacy runs identically everywhere.
    internal func captureStepMedia(
        context: RawElementContext?,
        at location: Point2D,
        stepIndex: Int,
        sessionID: String
    ) async -> StepMedia {
        var media = StepMedia()
        guard driver.capabilities.snapshots else { return media }
        guard var snapshot = await driver.captureSnapshot(highlightAt: location, stepIndex: stepIndex) else {
            return media
        }

        // 1. Pre-capture privacy (T6): blackout the secure field before the
        //    image is ever persisted.
        if context?.isSecure == true, let region = context?.boundingBox ?? context?.windowBounds,
           let obscuring = driver as? VisualObscuring {
            snapshot = await obscuring.obscureSensitiveRegions(in: snapshot, regions: [region], anchor: location)
        }

        // 2. Post-capture privacy (T7): offline OCR → sensitive regions → blur.
        if privacySettings.enableOfflineOCRRedaction, let redactor = driver as? VisualRedactionProviding {
            let preRedaction = snapshot
            let outcome = await redactor.redactSensitiveContent(in: snapshot, settings: privacySettings)
            if outcome.isRedacted {
                snapshot = outcome.snapshot
                media.isRedacted = true
                // Non-destructive redaction: keep the unblurred source so the
                // Review Window can toggle it.
                let originalName = String(format: "step_%02d.original.png", stepIndex)
                media.assets.screenshotOriginal = try? store.saveMedia(
                    data: preRedaction.pngData,
                    sessionID: sessionID,
                    filename: originalName
                )
            }
        }

        // 3. Persist the (possibly redacted) frame.
        let pngName = String(format: "step_%02d.png", stepIndex)
        if let relPath = try? store.saveMedia(data: snapshot.pngData, sessionID: sessionID, filename: pngName) {
            media.assets.screenshot = relPath
        }
        return media
    }


    /// Patches a step's assets (by id) once a micro-clip resolves, with the
    /// legacy `step_%02d.gif` / `step_%02d.mp4` naming.
    internal func patchAssets(stepID: String, gif: Data?, video: Data?) {
        guard var session = currentSession,
              let index = session.steps.firstIndex(where: { $0.id == stepID }) else { return }

        let filenameBase = String(format: "step_%02d", session.steps[index].index)
        var assets = session.steps[index].assets

        if let gif = gif {
            let gifName = "\(filenameBase).gif"
            if let relPath = try? store.saveMedia(data: gif, sessionID: session.id, filename: gifName) {
                assets.gif = relPath
            }
        }

        if let video = video {
            let mp4Name = "\(filenameBase).mp4"
            if let relPath = try? store.saveMedia(data: video, sessionID: session.id, filename: mp4Name) {
                assets.webm = relPath
            }
        }

        session.steps[index].assets = assets
        currentSession = session
        try? store.saveSession(session)
    }


    public func captureInstantSnapshot(at point: Point2D? = nil) async {
        let location = point ?? lastKnownLocation ?? .zero
        await handleAction(action: .manual, at: location, timestamp: time.now)
    }
}
