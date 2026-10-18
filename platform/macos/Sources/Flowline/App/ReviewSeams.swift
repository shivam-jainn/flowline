import Foundation
import FlowlineIR
import FlowlineAIGateway
import FlowlinePublishing

/// Review-surface seams (R/M1-07, app target only).
///
/// The existing module abstractions don't fit these call sites:
/// - `GatewayProvider.complete` is single-shot request/response, while the
///   review pane streams synthesis tokens.
/// - `SessionExporter.export(session:to:)` is per-format + untyped, while the
///   review pane drives the 3-format coordinator flow.
/// These two minimal protocols cover the gap; the module concretes conform
/// via extensions below with zero module edits.

/// Streaming AI synthesis for the review pane.
public protocol StepSynthesisService: Sendable {
    func generateStream(
        session: StepSession,
        settings: GatewaySettings,
        style: DocumentationStyle,
        customInstructions: String?
    ) -> AsyncThrowingStream<String, Error>
}

extension AIGatewayClient: StepSynthesisService {}

/// Multi-format publishing for the review pane.
public protocol ReviewPublishingService: Sendable {
    func exportWeb(session: StepSession, publishing: PublishingSettings) throws -> URL
    func exportPDF(session: StepSession, publishing: PublishingSettings) async throws -> URL
    func exportMarkdown(session: StepSession) throws -> URL
    func openInBrowser(url: URL)
    func revealInFinder(url: URL)
}

extension PublishingCoordinator: ReviewPublishingService {}
