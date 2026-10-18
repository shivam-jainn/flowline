import SwiftUI
import FlowlineIR
import FlowlineStorage

// MARK: - Library sorting / filtering (UI-only)

public enum LibrarySort: String, CaseIterable, Identifiable {
    case newest, oldest, mostSteps, title
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .mostSteps: return "Most steps"
        case .title: return "Title A–Z"
        }
    }
}

public enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, favorites, visuals
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .visuals: return "With visuals"
        }
    }
}

// MARK: - Library home (neat grid + hover-to-preview thumbnails)

/// Clean replacement for the old text-only `libraryHome`:
/// one search + chips + sort header, one adaptive grid, each card topped
/// with a static thumbnail that plays its step screenshots on hover
/// so duplicate "Workflow Recording" titles stay scannable without motion.
public struct FlowlineLibraryView: View {
    var sessions: [StepSession]
    var store: SessionStore
    @ObservedObject var meta: FlowlineMetaStore
    var onOpen: (StepSession) -> Void

    @State private var query: String = ""
    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .newest

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        sessions: [StepSession],
        store: SessionStore,
        meta: FlowlineMetaStore,
        onOpen: @escaping (StepSession) -> Void
    ) {
        self.sessions = sessions
        self.store = store
        self.meta = meta
        self.onOpen = onOpen
    }

    private var visible: [StepSession] {
        var list = sessions
        switch filter {
        case .all: break
        case .favorites: list = list.filter { meta.isFavorite($0.id) }
        case .visuals: list = list.filter { $0.steps.contains(where: { $0.assets.screenshot != nil || $0.assets.gif != nil }) }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || $0.steps.contains(where: { $0.actionDescription.localizedCaseInsensitiveContains(q) })
                    || $0.steps.contains(where: { $0.appName.localizedCaseInsensitiveContains(q) })
            }
        }
        switch sort {
        case .newest: list.sort { $0.startedAt > $1.startedAt }
        case .oldest: list.sort { $0.startedAt < $1.startedAt }
        case .mostSteps: list.sort { $0.steps.count > $1.steps.count }
        case .title: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return list
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                controls
                if visible.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(visible) { s in
                            FlowlineLibraryCard(
                                session: s,
                                store: store,
                                isFavorite: meta.isFavorite(s.id),
                                onToggleFavorite: { meta.toggleFavorite(s.id) },
                                onOpen: { onOpen(s) }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LIBRARY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                HStack(spacing: 8) {
                    Text("Recordings")
                        .font(.system(size: 24, weight: .bold))
                    Text("\(sessions.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(FlowComponent.for(scheme).textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(FlowComponent.for(scheme).surfaceSubtle)
                        .clipShape(Capsule())
                }
                Text("Raw captures waiting to become guides. Hover a card to preview its steps — click to edit.")
                    .font(.system(size: 12))
                    .foregroundColor(FlowComponent.for(scheme).textSecondary)
            }
            Spacer()
            Button(action: {}) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("Start recording").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(FlowComponent.for(scheme).primaryBg)
                .foregroundColor(FlowComponent.for(scheme).primaryFg)
                .cornerRadius(FlowComponent.radiusSM)
            }
            .buttonStyle(FlowPressStyle())
            .disabled(true)
            .help("Recording starts from the menu bar HUD")
        }
    }

    // MARK: - Search + chips + sort

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                TextField("Search recordings, steps, apps…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(FlowComponent.for(scheme).textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: 300)
            .background(FlowComponent.for(scheme).surface)
            .cornerRadius(FlowComponent.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .stroke(FlowComponent.for(scheme).border, lineWidth: 1)
            )

            ForEach(LibraryFilter.allCases) { f in
                Button(action: {
                    withAnimation(reduceMotion ? nil : FlowMotion.standardFast) { filter = f }
                }) {
                    Text(f.label)
                        .font(.system(size: 12, weight: filter == f ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(filter == f ? FlowSemantic.for(scheme).accentSubtle : FlowComponent.for(scheme).surface)
                        .foregroundColor(filter == f ? FlowSemantic.for(scheme).accentDefault : FlowComponent.for(scheme).textSecondary)
                        .cornerRadius(FlowComponent.radiusSM)
                        .overlay(
                            RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                                .stroke(filter == f ? FlowSemantic.for(scheme).accentBorder : FlowComponent.for(scheme).border, lineWidth: 1)
                        )
                }
                .buttonStyle(FlowPressStyle())
            }

            Spacer()

            if !query.isEmpty || filter != .all {
                Text("\(visible.count) of \(sessions.count)")
                    .font(.system(size: 11))
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
            }

            Menu {
                ForEach(LibrarySort.allCases) { s in
                    Button(action: { sort = s }) {
                        if sort == s { Image(systemName: "checkmark") }
                        Text(s.label)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11))
                    Text(sort.label)
                        .font(.system(size: 12))
                }
                .foregroundColor(FlowComponent.for(scheme).textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(FlowComponent.for(scheme).surface)
                .cornerRadius(FlowComponent.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                        .stroke(FlowComponent.for(scheme).border, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .help("Sort recordings")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(FlowComponent.for(scheme).textTertiary)
            Text(query.isEmpty ? "No recordings yet" : "No matches for “\(query)”")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FlowComponent.for(scheme).textPrimary)
            Text(query.isEmpty
                 ? "Record a workflow from the menu bar and it will appear here with a hover-to-preview thumbnail."
                 : "Try a different title, step, or app name — or clear the filter.")
                .font(.system(size: 12))
                .foregroundColor(FlowComponent.for(scheme).textSecondary)
            if !query.isEmpty || filter != .all {
                Button("Clear filters") {
                    query = ""
                    filter = .all
                }
                .buttonStyle(FlowPressStyle())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .background(FlowComponent.for(scheme).surface)
        .cornerRadius(FlowComponent.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: FlowComponent.radiusLG)
                .stroke(FlowComponent.for(scheme).border, lineWidth: 1)
        )
    }
}

// MARK: - Card (static thumbnail on top, plays on hover, tidy meta below)

private struct FlowlineLibraryCard: View {
    var session: StepSession
    var store: SessionStore
    var isFavorite: Bool
    var onToggleFavorite: () -> Void
    var onOpen: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    LibraryPreview(session: session, store: store, isHovering: hovering)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0 / 9.5, contentMode: .fit)
                        .clipped()
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: FlowComponent.radiusLG,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: FlowComponent.radiusLG
                            )
                        )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.title.isEmpty ? "Untitled recording" : session.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(t.textPrimary)
                            .lineLimit(2)
                            .frame(minHeight: 34, alignment: .leading)
                        Text("\(session.steps.count) steps · \(session.startedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 11))
                            .foregroundColor(t.textSecondary)
                            .lineLimit(1)
                        Text(cardSubtitle)
                            .font(.system(size: 11))
                            .foregroundColor(t.textTertiary)
                            .lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(t.surface)
                .cornerRadius(FlowComponent.radiusLG)
                .overlay(
                    RoundedRectangle(cornerRadius: FlowComponent.radiusLG)
                        .stroke(hovering ? sem.accentBorder : t.border, lineWidth: 1)
                )
                .shadow(
                    color: hovering ? sem.shadowDefault : sem.shadowSubtle,
                    radius: hovering ? 10 : 5, y: hovering ? 3 : 1
                )
                .animation(reduceMotion ? nil : FlowMotion.standardFast, value: hovering)
            }
            .buttonStyle(FlowPressStyle())
            .onHover { hovering = $0 }
            .help("\(session.title) — \(session.steps.count) steps. Open to edit.")

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isFavorite ? sem.accentDefault : t.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(t.border, lineWidth: 1))
                    .shadow(color: sem.shadowSubtle, radius: 3, y: 1)
            }
            .buttonStyle(FlowPressStyle())
            .opacity(isFavorite || hovering ? 1 : 0)
            .allowsHitTesting(isFavorite || hovering)
            .animation(reduceMotion ? nil : FlowMotion.standardFast, value: hovering)
            .animation(reduceMotion ? nil : FlowMotion.standardFast, value: isFavorite)
            .padding(8)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }
    }

    /// One-line differentiator so duplicate titles stay scannable:
    /// "Safari, Terminal · 12 visuals" or the first step's action.
    private var cardSubtitle: String {
        let visuals = session.steps.filter { $0.assets.screenshot != nil || $0.assets.gif != nil }.count
        let apps = Array(NSOrderedSet(array: session.steps.map(\.appName).filter { !$0.isEmpty }).array as? [String] ?? [])
        if apps.isEmpty, visuals == 0 {
            return session.steps.first?.actionDescription ?? "No steps yet"
        }
        let appBit = apps.prefix(2).joined(separator: ", ")
        if visuals > 0 {
            return "\(appBit)\(apps.count > 2 ? " +\(apps.count - 2)" : "") · \(visuals) visual\(visuals == 1 ? "" : "s")"
        }
        return appBit
    }
}

// MARK: - Hover-to-preview thumbnail (static until hovered)

/// Static thumbnail that plays the step screenshots (~1.5s each,
/// desynced per card) only while hovered, with a crossfade + segmented
/// progress bar, so the grid stays calm until the user asks for motion.
/// Static single frame when Reduce Motion is on or there is ≤1 visual.
private struct LibraryPreview: View {
    var session: StepSession
    var store: SessionStore
    var isHovering: Bool = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Up to 6 evenly-sampled visuals across the whole capture so the loop
    /// shows the *entire* flow, not just the first frames.
    private var frames: [(url: URL, key: String)] {
        let withVisuals = session.steps.compactMap { s -> (URL, String)? in
            if let shot = s.assets.screenshot {
                let url = store.resolveMediaPath(sessionID: session.id, relativePath: shot)
                return (url, "shot:\(session.id)/\(s.id)/\(shot)")
            }
            if let gif = s.assets.gif {
                let url = store.resolveMediaPath(sessionID: session.id, relativePath: gif)
                return (url, "gif:\(session.id)/\(s.id)/\(gif)")
            }
            return nil
        }
        guard withVisuals.count > 6 else { return withVisuals }
        let stride = Double(withVisuals.count) / 6.0
        return (0..<6).map { i in withVisuals[min(withVisuals.count - 1, Int(Double(i) * stride))] }
    }

    /// Per-card offset so a 23-card grid doesn't flip in lockstep.
    private var offset: Double {
        var h: UInt64 = 5381
        for b in session.id.utf8 { h = h &* 33 &+ UInt64(b) }
        return Double(h % 1500) / 1000.0
    }

    var body: some View {
        let t = FlowComponent.for(scheme)
        let items = frames
        ZStack {
            t.surfaceSubtle
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: session.steps.isEmpty ? "tray" : "photo")
                        .font(.system(size: 22))
                        .foregroundColor(t.textTertiary)
                    Text(session.steps.isEmpty ? "Empty capture" : "\(session.steps.count) steps · no visuals")
                        .font(.system(size: 11))
                        .foregroundColor(t.textTertiary)
                }
            } else if items.count == 1 || reduceMotion {
                LibraryFrame(url: items[0].url, cacheKey: items[0].key)
            } else if !isHovering {
                LibraryFrame(url: items[0].url, cacheKey: items[0].key)
            } else {
                TimelineView(.periodic(from: Date().addingTimeInterval(offset), by: 1.5)) { timeline in
                    let idx = Int((timeline.date.timeIntervalSince1970 + offset) / 1.5) % items.count
                    LibraryFrame(url: items[idx].url, cacheKey: items[idx].key)
                        .id(items[idx].key)
                        .transition(.opacity)
                        .animation(FlowMotion.standard, value: idx)
                    progressOverlay(index: idx, count: items.count)
                    stepBadge
                }
            }
            if items.count <= 1 || reduceMotion || !isHovering {
                stepBadge
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.surfaceSubtle)
    }

    private var stepBadge: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 5) {
                    if frames.count > 1, !reduceMotion {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 8))
                    }
                    Text("\(session.steps.count) step\(session.steps.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                Spacer()
                if frames.count > 1, !reduceMotion {
                    Text("preview")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                }
            }
            .padding(8)
        }
    }

    private func progressOverlay(index: Int, count: Int) -> some View {
        VStack {
            HStack(spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(i == index ? 0.95 : (i < index ? 0.6 : 0.35)))
                        .frame(height: 2.5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .shadow(color: .black.opacity(0.3), radius: 2)
            Spacer()
        }
    }
}

// MARK: - Cached async frame (body never touches disk)

private struct LibraryFrame: View {
    var url: URL
    var cacheKey: String
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { _ in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    Color.clear
                }
            }
            .task(id: cacheKey) {
                if let hit = LibraryPreviewCache.shared.image(forKey: cacheKey) {
                    image = hit
                } else {
                    image = await LibraryPreviewCache.shared.load(url: url, key: cacheKey)
                }
            }
        }
    }
}

private final class LibraryPreviewCache: @unchecked Sendable {
    static let shared = LibraryPreviewCache()
    private let cache = NSCache<NSString, NSImage>()
    func image(forKey key: String) -> NSImage? { cache.object(forKey: key as NSString) }
    func load(url: URL, key: String) async -> NSImage? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                guard let img = NSImage(contentsOf: url) else {
                    cont.resume(returning: nil)
                    return
                }
                self.cache.setObject(img, forKey: key as NSString)
                cont.resume(returning: img)
            }
        }
    }
}
