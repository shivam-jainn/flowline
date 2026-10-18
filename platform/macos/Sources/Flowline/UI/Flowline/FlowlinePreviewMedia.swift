import SwiftUI
import FlowlineIR
import FlowlineStorage

/// Shared media block for both previews (side pane + fullscreen Preview).
/// Shows what the step will look like: the captured screenshot, or the
/// animated GIF when the step prefers it — the same rule as the canvas
/// (`FlowlineStage.previewURL`) and the web export (GIF when captured).
///
/// GIFs play via `AnimatedGIFView` (`NSImageView.animates`, same as the
/// legacy steps pane); stills load off the main thread through a small
/// `NSCache` so long step lists don't jank. No media → the caller renders
/// nothing (the web export likewise omits the media block).
struct PreviewMediaView: View {
    var step: Step
    var sessionID: String
    var store: SessionStore
    /// Max height for the fitted image (side pane ~150, fullscreen ~340).
    var maxHeight: CGFloat = 150

    @Environment(\.colorScheme) private var scheme

    /// Resolve the display asset: GIF when preferred/captured, else still.
    /// Mirrors `FlowlineStage.previewURL`.
    static func resolve(step: Step, sessionID: String, store: SessionStore) -> (url: URL, animated: Bool)? {
        let wantsGIF = (step.preferredMedia?.lowercased() == "gif")
            || (step.preferredMedia == nil && step.assets.gif != nil)
        if wantsGIF, let g = step.assets.gif {
            return (store.resolveMediaPath(sessionID: sessionID, relativePath: g), true)
        }
        if let p = step.assets.screenshot {
            return (store.resolveMediaPath(sessionID: sessionID, relativePath: p), false)
        }
        return nil
    }

    var body: some View {
        if let media = Self.resolve(step: step, sessionID: sessionID, store: store) {
            ZStack(alignment: .topTrailing) {
                if media.animated {
                    AnimatedGIFView(url: media.url)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: maxHeight)
                        .clipped()
                } else {
                    PreviewStill(url: media.url, maxHeight: maxHeight)
                }
                if media.animated {
                    Text("GIF")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.65))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
            .cornerRadius(FlowComponent.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .stroke(FlowComponent.for(scheme).borderSubtle, lineWidth: 1)
            )
        } else if FlowlineStepText.isPlaceholder(step) {
            // Placeholder steps never render as empty space: a badged
            // "no capture" well instead of a bare photo icon. Steps with
            // real text but no media still render nothing (web parity).
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 18))
                .foregroundColor(FlowComponent.for(scheme).textTertiary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(8)
                .background(FlowComponent.for(scheme).surfaceSubtle.opacity(0.6))
                .cornerRadius(FlowComponent.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                        .stroke(FlowComponent.for(scheme).borderSubtle, lineWidth: 1)
                )
                .help("No capture")
                .accessibilityLabel("Step needs instructions — no capture")
        }
    }
}

/// Async still-image loader (never touches disk in the body path).
private struct PreviewStill: View {
    var url: URL
    var maxHeight: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
                    .frame(height: 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .task(id: url.path) {
            if let hit = PreviewMediaCache.shared.image(forKey: url.path) {
                image = hit
            } else {
                image = await PreviewMediaCache.shared.load(url: url)
            }
        }
    }
}

private final class PreviewMediaCache {
    static let shared = PreviewMediaCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func load(url: URL) async -> NSImage? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                guard let img = NSImage(contentsOf: url) else {
                    cont.resume(returning: nil)
                    return
                }
                self.cache.setObject(img, forKey: url.path as NSString)
                cont.resume(returning: img)
            }
        }
    }
}
