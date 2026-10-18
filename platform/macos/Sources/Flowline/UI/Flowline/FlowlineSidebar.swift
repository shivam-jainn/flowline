import SwiftUI
import FlowlineIR
import FlowlineStorage

/// Left organizer: search + Library + Favorites + Folders
/// (2-level tree) + Ungrouped tail, with a sticky footer.
/// Port of prototype `<aside class="sidebar">` — folders, favorites
/// and width persist in `FlowlineMetaStore` so the IR stays untouched.
public struct FlowlineSidebar: View {
    @Binding var session: StepSession
    var sessions: [StepSession]
    var view: FlowlineEditorView
    @ObservedObject var meta: FlowlineMetaStore
    var onSelectView: (FlowlineEditorView) -> Void
    var onSelectSession: (StepSession) -> Void
    var onRenameSession: (String, String) -> Void
    var onMoveSession: (String, String?) -> Void
    var onDeleteSession: (String) -> Void
    var onDuplicateSession: (String) -> Void
    var onOpenSettings: () -> Void

    @State private var query: String = ""
    @State private var hoverID: String?
    @State private var renamingSessionID: String?
    @State private var renameText: String = ""
    @State private var renamingFolderID: String?
    @State private var folderRenameText: String = ""
    @State private var pendingNewFolderID: String?
    @State private var showAllUngrouped = false
    @State private var smart: SmartGroup?
    @State private var pickerFolderID: String?
    @State private var moveSessionID: String?
    @State private var pendingDeleteFolderID: String?
    @State private var pendingDeleteSessionID: String?
    @State private var folderUndo: FlowlineMetaStore.FolderBackup?
    @State private var dropTargetID: String?
    @State private var focusedFolderID: String?
    @State private var resizeStartWidth: Double?
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    enum SmartGroup: String { case favorites }

    public init(
        session: Binding<StepSession>,
        sessions: [StepSession],
        view: FlowlineEditorView,
        meta: FlowlineMetaStore,
        onSelectView: @escaping (FlowlineEditorView) -> Void,
        onSelectSession: @escaping (StepSession) -> Void,
        onRenameSession: @escaping (String, String) -> Void = { _, _ in },
        onMoveSession: @escaping (String, String?) -> Void = { _, _ in },
        onDeleteSession: @escaping (String) -> Void = { _ in },
        onDuplicateSession: @escaping (String) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void
    ) {
        self._session = session
        self.sessions = sessions
        self.view = view
        self._meta = ObservedObject(wrappedValue: meta)
        self.onSelectView = onSelectView
        self.onSelectSession = onSelectSession
        self.onRenameSession = onRenameSession
        self.onMoveSession = onMoveSession
        self.onDeleteSession = onDeleteSession
        self.onDuplicateSession = onDuplicateSession
        self.onOpenSettings = onOpenSettings
    }

    // MARK: - Derived

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var filtered: [StepSession] {
        guard isSearching else { return sessions }
        return sessions.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.steps.contains(where: { $0.actionDescription.localizedCaseInsensitiveContains(query) })
        }
    }

    var favoritesAll: [StepSession] {
        sessions.filter { meta.isFavorite($0.id) }.sorted(by: { $0.startedAt > $1.startedAt })
    }

    var favoritesFiltered: [StepSession] {
        isSearching
            ? filtered.filter { meta.isFavorite($0.id) }
            : favoritesAll
    }

    var ungroupedAll: [StepSession] {
        sessions.filter { meta.sessionFolder[$0.id] == nil }.sorted(by: { $0.startedAt > $1.startedAt })
    }

    var ungroupedFiltered: [StepSession] {
        isSearching
            ? filtered.filter { meta.sessionFolder[$0.id] == nil }
            : ungroupedAll
    }

    /// Session ids in visual keyboard order (workspace depth-first, then tail).
    var keyboardOrder: [String] {
        var ids: [String] = []
        for f in visibleTopFolders {
            for g in guidesForKeyboard(in: f.id) { ids.append(g.id) }
            for sub in visibleSubfolders(of: f.id) {
                for g in guidesForKeyboard(in: sub.id) { ids.append(g.id) }
            }
        }
        for s in visibleUngroupedTailFull { ids.append(s.id) }
        return ids
    }

    // MARK: - Body (sticky search + scroll + sticky footer, resizable)

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchHeader
                    .padding(12)
                    .padding(.bottom, 0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        librarySection
                        if !favoritesFiltered.isEmpty { favoritesSection }
                        workspaceSection
                        if isSearching && filtered.isEmpty { searchEmptyState }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .focusable()
                .focused($listFocused)
                .onKeyPress { press in handleKeyPress(press) }
                if folderUndo != nil { folderUndoBar }
                footer
                    .padding(12)
            }
            .frame(width: CGFloat(meta.sidebarWidth))
            .background(FlowComponent.for(scheme).canvas)
            dragHandle
        }
        .confirmationDialog(
            "Delete this folder and its subfolders? Guides become Ungrouped.",
            isPresented: Binding(get: { pendingDeleteFolderID != nil }, set: { if !$0 { pendingDeleteFolderID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete folder", role: .destructive) { confirmDeleteFolder() }
            Button("Cancel", role: .cancel) { pendingDeleteFolderID = nil }
        }
        .confirmationDialog(
            "Delete this guide? This removes its Steps.",
            isPresented: Binding(get: { pendingDeleteSessionID != nil }, set: { if !$0 { pendingDeleteSessionID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete guide", role: .destructive) { confirmDeleteSession() }
            Button("Cancel", role: .cancel) { pendingDeleteSessionID = nil }
        }
        .popover(isPresented: Binding(get: { pickerFolderID != nil }, set: { if !$0 { pickerFolderID = nil } })) {
            if let id = pickerFolderID, let f = meta.folders.first(where: { $0.id == id }) {
                folderStylePicker(f)
            }
        }
        .popover(isPresented: Binding(get: { moveSessionID != nil }, set: { if !$0 { moveSessionID = nil } })) {
            movePopover
        }
    }

    // MARK: - Search (sticky top, ⌘K, Esc clears)

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
                TextField("Search guides and recordings", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                    .onExitCommand {
                        if !query.isEmpty { query = "" } else { searchFocused = false }
                    }
                    .onSubmit { listFocused = true }
                    .accessibilityLabel("Search guides and recordings")
                    .help("Search by guide title or step text (⌘K to focus, Esc to clear)")
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(FlowComponent.for(scheme).textTertiary)
                    }
                    .buttonStyle(FlowPressStyle())
                    .help("Clear search (Esc)")
                    .accessibilityLabel("Clear search")
                } else {
                    Button(action: { searchFocused = true }) {
                        Text("⌘K")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(FlowComponent.for(scheme).textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .background(FlowComponent.for(scheme).surfaceSubtle)
                            .cornerRadius(FlowComponent.radiusXS)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("k", modifiers: .command)
                    .help("Focus search (⌘K)")
                    .accessibilityLabel("Focus search")
                }
            }
            .padding(8)
            .background(FlowComponent.for(scheme).surface)
            .cornerRadius(FlowComponent.radiusSM)
            .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(FlowComponent.for(scheme).border, lineWidth: 1))
            if isSearching {
                Text("\(filtered.count) result\(filtered.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                    .padding(.horizontal, 4)
                    .accessibilityLabel("\(filtered.count) search results")
            }
        }
    }

    private var searchEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No results for “\(query)”")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FlowComponent.for(scheme).textSecondary)
            Button("Clear search") { query = "" }
                .buttonStyle(FlowPressStyle())
                .font(.system(size: 12))
                .foregroundColor(FlowSemantic.for(scheme).accentDefault)
        }
        .padding(.horizontal, 4)
        .accessibilityLabel("No search results")
    }

    // MARK: - Library + Smart Groups

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SideRow(
                selected: view == .library && smart == nil,
                focused: listFocused && view == .library && smart == nil,
                hoverID: $hoverID, id: "__library", height: 28,
                action: { selectLibrary() }
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12))
                        .foregroundColor(view == .library && smart == nil ? FlowSemantic.for(scheme).accentDefault : FlowComponent.for(scheme).textSecondary)
                        .frame(width: 14)
                    Text("Library")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
            }
            .help("All guides")
            .accessibilityLabel("Library, all guides")
            if !favoritesAll.isEmpty {
                SideRow(
                    selected: smart == .favorites,
                    focused: false,
                    hoverID: $hoverID, id: "__fav", height: 28,
                    action: { withMotion { smart = (smart == .favorites ? nil : .favorites) } }
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "star")
                            .font(.system(size: 12))
                            .foregroundColor(smart == .favorites ? FlowSemantic.for(scheme).accentDefault : FlowComponent.for(scheme).textSecondary)
                            .frame(width: 14)
                        Text("Favorites")
                            .font(.system(size: 12))
                        Spacer()
                        CountPill("\(favoritesAll.count)")
                    }
                }
                .help("Guides you starred")
                .accessibilityLabel("Favorites smart group, \(favoritesAll.count) guides")
            }
        }
    }

    private func selectLibrary() {
        withMotion {
            smart = nil
            onSelectView(.library)
        }
    }

    // MARK: - Favorites section (hidden when empty)

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Favorites", count: favoritesFiltered.count)
            ForEach(favoritesFiltered) { s in guideRow(s, subtitle: folderPath(for: s.id)) }
        }
    }

    // MARK: - Workspace (2-level tree + Ungrouped tail)

    private var visibleTopFolders: [FlowFolder] {
        let tops = meta.topLevelFolders
        guard isSearching else { return smartFilteredFolders(tops) }
        return tops.filter { folderVisibleWhenSearching($0) }
    }

    private func smartFilteredFolders(_ tops: [FlowFolder]) -> [FlowFolder] {
        guard smart == .favorites else { return tops }
        return tops.filter { folderContainsFavorite($0) }
    }

    private func folderContainsFavorite(_ f: FlowFolder) -> Bool {
        guidesInFolder(f.id).contains(where: { meta.isFavorite($0.id) })
            || subfolders(of: f.id).contains(where: { guidesInFolder($0.id).contains(where: { meta.isFavorite($0.id) }) })
    }

    private func visibleSubfolders(of folderID: String) -> [FlowFolder] {
        let subs = subfolders(of: folderID)
        guard isSearching else { return subs }
        return subs.filter { sub in
            sub.name.localizedCaseInsensitiveContains(query)
                || guidesInFolder(sub.id).contains(where: { guideMatches($0) })
        }
    }

    private func folderVisibleWhenSearching(_ f: FlowFolder) -> Bool {
        if f.name.localizedCaseInsensitiveContains(query) { return true }
        if guidesInFolder(f.id).contains(where: { guideMatches($0) }) { return true }
        return !visibleSubfolders(of: f.id).isEmpty
    }

    private func guideMatches(_ s: StepSession) -> Bool {
        filtered.contains(where: { $0.id == s.id })
    }

    private func subfolders(of folderID: String) -> [FlowFolder] {
        meta.subfolders(of: folderID)
    }

    private func guidesInFolder(_ folderID: String) -> [StepSession] {
        let base = isSearching ? filtered : sessions
        var guides = base.filter { meta.sessionFolder[$0.id] == folderID }
        if smart == .favorites { guides = guides.filter { meta.isFavorite($0.id) } }
        return guides.sorted(by: { $0.startedAt > $1.startedAt })
    }

    private func guidesForKeyboard(in folderID: String) -> [StepSession] {
        guidesInFolder(folderID)
    }

    private var visibleUngroupedTailFull: [StepSession] {
        if smart == .favorites { return ungroupedFiltered.filter { meta.isFavorite($0.id) } }
        return ungroupedFiltered
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                sectionHeader("Folders", count: nil)
                Spacer(minLength: 8)
                Button(action: { createAndRenameFolder() }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                        .foregroundColor(FlowComponent.for(scheme).textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlowPressStyle())
                .help("New folder")
                .accessibilityLabel("New folder")
            }
            ForEach(visibleTopFolders) { folder in folderBlockL0(folder) }
            if smart != .favorites {
                ungroupedTail
            }
            if !isSearching && visibleTopFolders.isEmpty && visibleUngroupedTailFull.isEmpty && smart == nil {
                Text("No guides yet — record to create your first guide.")
                    .font(.system(size: 11))
                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    // L0 block: folder + its L1 subfolders + its guides. Non-recursive
    // (max depth 2): L1 renders guides only, never deeper folders.
    @ViewBuilder
    private func folderBlockL0(_ folder: FlowFolder) -> some View {
        let collapsed = isSearching ? false : meta.isCollapsed(folder.id)
        let guides = guidesInFolder(folder.id)
        let subs = isSearching ? visibleSubfolders(of: folder.id) : subfolders(of: folder.id)
        VStack(alignment: .leading, spacing: 4) {
            folderRow(folder, depth: 0, collapsed: collapsed, guideCount: guides.count + subs.reduce(0) { $0 + guidesInFolder($1.id).count })
            if !collapsed {
                ForEach(subs) { sub in subfolderBlock(sub) }
                ForEach(guides) { s in
                    guideRow(s, subtitle: nil, depth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func subfolderBlock(_ sub: FlowFolder) -> some View {
        let collapsed = isSearching ? false : meta.isCollapsed(sub.id)
        let guides = guidesInFolder(sub.id)
        VStack(alignment: .leading, spacing: 4) {
            folderRow(sub, depth: 1, collapsed: collapsed, guideCount: guides.count)
            if !collapsed {
                ForEach(guides) { s in
                    guideRow(s, subtitle: nil, depth: 2)
                }
            }
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: FlowFolder, depth: Int, collapsed: Bool, guideCount: Int) -> some View {
        let isDropTarget = dropTargetID == folder.id
        let hovering = hoverID == folder.id
        let focused = focusedFolderID == folder.id
        let showToolbar = hovering || focused || pickerFolderID == folder.id || isDropTarget
        Group {
            // Renaming renders outside the toggle Button so clicks in the
            // field can't fire the collapse toggle.
            if renamingFolderID == folder.id {
                HStack(spacing: 6) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(FlowComponent.for(scheme).textTertiary)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    Image(systemName: folder.icon)
                        .font(.system(size: 12))
                        .foregroundColor(folder.color(for: scheme))
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    RenameField(
                        text: $folderRenameText, placeholder: "Folder name",
                        onCommit: { commitFolderRename(folder) },
                        onCancel: { cancelFolderRename(folder) }
                    )
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.leading, CGFloat(4 + depth * 12))
                .frame(minHeight: 30, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FlowComponent.for(scheme).surface)
                .cornerRadius(FlowComponent.radiusSM)
            } else {
                // Card: single HStack so toolbar is in-flow (flexbox),
                // never overlayed. Space is always reserved, only opacity
                // toggles — cursor can't lose it mid-travel, text never
                // slides under the icons.
                HStack(spacing: 0) {
                    Button(action: {
                        focusedFolderID = folder.id
                        withMotion { meta.toggleCollapsed(folder.id) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(FlowComponent.for(scheme).textTertiary)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Image(systemName: folder.icon)
                                .font(.system(size: 12))
                                .foregroundColor(folder.color(for: scheme))
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Text(folder.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(FlowComponent.for(scheme).textPrimary)
                                .lineLimit(1)
                                .layoutPriority(1)
                            if guideCount > 0 { CountPill("\(guideCount)") }
                        }
                        .padding(.vertical, 6)
                        .frame(minHeight: 30, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FlowPressStyle())
                    .help(folderHelp(folder, collapsed: collapsed))
                    .accessibilityLabel("\(depth == 0 ? "Folder" : "Subfolder") \(folder.name), \(guideCount) guides")
                    folderHoverToolbar(folder, depth: depth)
                        .opacity(showToolbar ? 1 : 0)
                        .allowsHitTesting(showToolbar)
                }
                .padding(.leading, CGFloat(4 + depth * 12))
                .padding(.trailing, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isDropTarget ? FlowSemantic.for(scheme).accentSubtle : (hovering || focused ? FlowComponent.for(scheme).sideBgHover : FlowComponent.for(scheme).sideBg))
                .cornerRadius(FlowComponent.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                        .stroke(isDropTarget ? FlowSemantic.for(scheme).accentDefault : (focused ? FlowSemantic.for(scheme).focusRing : Color.clear), lineWidth: isDropTarget || focused ? 1 : 0)
                )
            }
        }
        .onHover { hoverID = $0 ? folder.id : (hoverID == folder.id ? nil : hoverID) }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onMoveSession(id, folder.id)
            dropTargetID = nil
            return true
        } isTargeted: { targeted in
            dropTargetID = targeted ? folder.id : (dropTargetID == folder.id ? nil : dropTargetID)
        }
        .contextMenu { folderMenu(folder, depth: depth) }
    }

    private func folderHelp(_ folder: FlowFolder, collapsed: Bool) -> String {
        "\(folder.name) — click to \(collapsed ? "expand" : "collapse")"
    }

    @ViewBuilder
    private func folderHoverToolbar(_ folder: FlowFolder, depth: Int) -> some View {
        HStack(spacing: 0) {
            if depth == 0 {
                Button(action: {
                    withMotion {
                        if let sub = meta.createFolder(name: "New subfolder", parentID: folder.id) {
                            meta.setCollapsed(folder.id, collapsed: false)
                            pendingNewFolderID = sub.id
                            renamingFolderID = sub.id
                            folderRenameText = sub.name
                        }
                    }
                }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                        .foregroundColor(FlowComponent.for(scheme).textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlowPressStyle())
                .help("New subfolder in \(folder.name)")
                .accessibilityLabel("New subfolder in \(folder.name)")
            }
            Button(action: {
                pickerFolderID = folder.id
            }) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 12))
                    .foregroundColor(FlowComponent.for(scheme).textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FlowPressStyle())
            .help("Folder color and icon")
            .accessibilityLabel("Folder color and icon for \(folder.name)")
        }
    }

    @ViewBuilder
    private func folderMenu(_ folder: FlowFolder, depth: Int) -> some View {
        Button("Rename") {
            renamingFolderID = folder.id
            folderRenameText = folder.name
        }
        Button("Color and icon…") { pickerFolderID = folder.id }
        if depth == 0 {
            Button("New subfolder") {
                withMotion {
                    if let sub = meta.createFolder(name: "New subfolder", parentID: folder.id) {
                        meta.setCollapsed(folder.id, collapsed: false)
                        pendingNewFolderID = sub.id
                        renamingFolderID = sub.id
                        folderRenameText = sub.name
                    }
                }
            }
        }
        Button(focusedFolderID == folder.id ? "Unfocus" : "Focus for keyboard") {
            focusedFolderID = (focusedFolderID == folder.id ? nil : folder.id)
        }
        Button("Collapse all") {
            withMotion { meta.collapseAll() }
        }
        Divider()
        Button("Delete folder…", role: .destructive) {
            pendingDeleteFolderID = folder.id
        }
    }

    private var ungroupedTail: some View {
        VStack(alignment: .leading, spacing: 4) {
            let all = visibleUngroupedTailFull
            let shown = (isSearching || showAllUngrouped) ? all : Array(all.prefix(5))
            if !all.isEmpty || isSearching {
                HStack(spacing: 6) {
                    Text("Ungrouped")
                        .font(.system(size: headerFontSize, weight: .semibold))
                        .foregroundColor(FlowComponent.for(scheme).textTertiary)
                    if all.count > 0 { CountPill("\(all.count)") }
                    Spacer()
                }
                .frame(minHeight: 22)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Ungrouped, \(all.count) guides")
            }
            ForEach(shown) { s in
                guideRow(s, subtitle: isSearching ? "Ungrouped" : nil, depth: 0)
            }
            if !isSearching && all.count > 5 {
                let remaining = all.count - shown.count
                Button(showAllUngrouped ? "Show less" : "Show \(remaining) more") {
                    withMotion { showAllUngrouped.toggle() }
                }
                .buttonStyle(FlowPressStyle())
                .font(.system(size: 11))
                .foregroundColor(FlowComponent.for(scheme).textTertiary)
                .padding(.horizontal, 8)
                .help(showAllUngrouped ? "Show fewer ungrouped guides" : "Show \(remaining) more ungrouped guides")
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            onMoveSession(id, nil)
            return true
        } isTargeted: { _ in }
    }

    // MARK: - Guide rows (draggable, favorite star, move/delete)

    @ViewBuilder
    private func guideRow(_ s: StepSession, subtitle: String? = nil, depth: Int = 0) -> some View {
        let selected = (s.id == session.id && view == .editor) || moveSessionID == s.id
        let favorited = meta.isFavorite(s.id)
        let hovering = hoverID == s.id
        let showStar = hovering || favorited || selected
        if renamingSessionID == s.id {
            RenameField(text: $renameText, placeholder: "Guide name", onCommit: { commitRename(s) }, onCancel: { renamingSessionID = nil })
                .padding(.horizontal, 8)
                .padding(.leading, CGFloat(4 + depth * 12))
                .frame(minHeight: 28)
                .background(FlowComponent.for(scheme).surface)
                .cornerRadius(FlowComponent.radiusSM)
        } else {
            // Card: HStack in-flow (flexbox), star slot always reserved.
            // No ZStack overlay, no layout shift, no overlap.
            HStack(spacing: 0) {
                Button(action: {
                    focusedFolderID = meta.sessionFolder[s.id]
                    withMotion {
                        smart = nil
                        if s.id == session.id { onSelectView(.editor) } else { onSelectSession(s) }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: s.id == session.id ? "doc.richtext.fill" : "doc.richtext")
                            .font(.system(size: 12))
                            .foregroundColor(s.id == session.id ? FlowSemantic.for(scheme).accentDefault : FlowComponent.for(scheme).textSecondary)
                            .frame(width: 14)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if let subtitle {
                                Text(subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(FlowComponent.for(scheme).textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .layoutPriority(1)
                        Spacer(minLength: 4)
                        Text("\(s.steps.count)")
                            .font(.system(size: 10))
                            .foregroundColor(FlowComponent.for(scheme).textTertiary)
                            .accessibilityHidden(true)
                            .help("\(s.steps.count) steps")
                    }
                    .padding(.vertical, 6)
                    .frame(minHeight: subtitle == nil ? 28 : 32, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FlowPressStyle())
                .help("\(s.title) — \(s.steps.count) steps")
                .accessibilityLabel("Guide \(s.title), \(s.steps.count) steps\(subtitle.map { ", in \($0)" } ?? "")")
                .accessibilityAddTraits(selected ? .isSelected : [])
                Button(action: { withMotion { meta.toggleFavorite(s.id) } }) {
                    Image(systemName: favorited ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(favorited ? FlowSemantic.for(scheme).accentDefault : FlowComponent.for(scheme).textTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FlowPressStyle())
                .opacity(showStar ? 1 : 0.3)
                .help(favorited ? "Remove from Favorites" : "Add to Favorites")
                .accessibilityLabel(favorited ? "Remove \(s.title) from favorites" : "Add \(s.title) to favorites")
            }
            .padding(.leading, CGFloat(4 + depth * 12))
            .padding(.trailing, 2)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? FlowComponent.for(scheme).sideBgSelected : (hovering ? FlowComponent.for(scheme).sideBgHover : FlowComponent.for(scheme).sideBg))
            .cornerRadius(FlowComponent.radiusSM)
            .overlay(
                RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                    .stroke((listFocused && s.id == session.id) ? FlowSemantic.for(scheme).focusRing : Color.clear, lineWidth: (listFocused && s.id == session.id) ? 2 : 0)
            )
            .onHover { hoverID = $0 ? s.id : (hoverID == s.id ? nil : hoverID) }
            .draggable(s.id)
            .contextMenu { guideMenu(s) }
        }
    }

    @ViewBuilder
    private func guideMenu(_ s: StepSession) -> some View {
        Button("Open") { onSelectSession(s) }
        Button("Rename") { startRenameSession(s) }
        Button(meta.isFavorite(s.id) ? "Remove from Favorites" : "Add to Favorites") {
            withMotion { meta.toggleFavorite(s.id) }
        }
        Menu("Move to…") {
            Button("Ungrouped") { onMoveSession(s.id, nil) }
            ForEach(meta.topLevelFolders) { f in
                Button(f.name) { onMoveSession(s.id, f.id) }
                ForEach(meta.subfolders(of: f.id)) { sub in
                    Button("\(f.name) / \(sub.name)") { onMoveSession(s.id, sub.id) }
                }
            }
            Divider()
            Button("New folder…") {
                if let f = meta.createFolder() { onMoveSession(s.id, f.id) }
            }
        }
        Button("Move… (M)") { moveSessionID = s.id }
        Button("Duplicate guide") { onDuplicateSession(s.id) }
        Divider()
        Button("Delete guide…", role: .destructive) { pendingDeleteSessionID = s.id }
    }

    // MARK: - Footer (sticky bottom)

    private var footer: some View {
        SideRow(
            selected: false,
            hoverID: $hoverID, id: "__settings", height: 28,
            action: onOpenSettings
        ) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(FlowComponent.for(scheme).textSecondary)
                    .frame(width: 14)
                Text("Settings")
                    .font(.system(size: 12))
                Spacer()
            }
        }
        .help("Settings")
        .accessibilityLabel("Settings")
        .padding(.top, 8)
    }

    // MARK: - Drag handle (resizable 180–320, persisted)

    private var dragHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(hoverID == "__resize" ? FlowSemantic.for(scheme).accentDefault.opacity(0.6) : Color.clear)
                    .frame(width: 1)
            )
            .onHover { hoverID = $0 ? "__resize" : (hoverID == "__resize" ? nil : hoverID) }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { g in
                        if resizeStartWidth == nil { resizeStartWidth = meta.sidebarWidth }
                        meta.setSidebarWidth((resizeStartWidth ?? FlowlineMetaStore.defaultSidebarWidth) + Double(g.translation.width))
                    }
                    .onEnded { _ in resizeStartWidth = nil }
            )
            .help("Drag to resize the sidebar")
            .accessibilityLabel("Resize sidebar")
    }

    // MARK: - Folder undo bar

    private var folderUndoBar: some View {
        HStack(spacing: 8) {
            Text("Folder deleted")
                .font(.system(size: 12))
                .foregroundColor(FlowComponent.for(scheme).textPrimary)
            Spacer()
            Button("Undo") {
                withMotion {
                    if let b = folderUndo { meta.restoreFolders(b) }
                    folderUndo = nil
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(FlowSemantic.for(scheme).accentDefault)
            .buttonStyle(FlowPressStyle())
            .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(FlowComponent.for(scheme).surfaceElevated)
        .cornerRadius(FlowComponent.radiusSM)
        .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusSM).stroke(FlowComponent.for(scheme).border, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withMotion { folderUndo = nil }
            }
        }
        .accessibilityLabel("Folder deleted. Undo available.")
    }

    // MARK: - Pickers / popovers

    private func folderStylePicker(_ folder: FlowFolder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folder style").font(.system(size: 13, weight: .semibold))
            Text("COLOR").font(.system(size: 10, weight: .semibold)).foregroundColor(FlowComponent.for(scheme).textTertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 6), spacing: 8) {
                ForEach(FlowPrimitive.UserFolder.paletteHex, id: \.self) { hex in
                    Button(action: { withMotion { meta.setFolderColor(folder.id, hex: hex) } }) {
                        Circle()
                            .fill(FlowPrimitive.UserFolder.color(hex: hex) ?? FlowComponent.for(scheme).textSecondary)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(FlowComponent.for(scheme).textInverse, lineWidth: folder.colorHex == hex ? 2 : 0))
                    }
                    .buttonStyle(FlowPressStyle())
                    .help("Folder color \(hex)")
                    .accessibilityLabel("Folder color \(hex)")
                }
            }
            Text("ICON").font(.system(size: 10, weight: .semibold)).foregroundColor(FlowComponent.for(scheme).textTertiary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 4), spacing: 8) {
                ForEach(folderIcons, id: \.self) { icon in
                    Button(action: { withMotion { meta.setFolderIcon(folder.id, icon: icon) } }) {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundColor(folder.icon == icon ? FlowSemantic.for(scheme).accentDefault : FlowComponent.for(scheme).textSecondary)
                            .frame(width: 32, height: 28)
                            .background(folder.icon == icon ? FlowSemantic.for(scheme).accentSubtle : FlowComponent.for(scheme).surfaceSubtle)
                            .cornerRadius(FlowComponent.radiusXS)
                    }
                    .buttonStyle(FlowPressStyle())
                    .help(icon)
                    .accessibilityLabel("Folder icon \(icon)")
                }
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    private var folderIcons: [String] {
        ["folder", "folder.fill", "star", "bookmark", "briefcase", "books.vertical", "film", "music.note"]
    }

    private var movePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Move to…").font(.system(size: 13, weight: .semibold))
            if let id = moveSessionID, let s = sessions.first(where: { $0.id == id }) {
                Text(s.title).font(.system(size: 11)).foregroundColor(FlowComponent.for(scheme).textSecondary).lineLimit(1)
            }
            Divider()
            Button(action: {
                if let id = moveSessionID { onMoveSession(id, nil) }
                moveSessionID = nil
            }) {
                HStack { Image(systemName: "tray").frame(width: 14); Text("Ungrouped").font(.system(size: 12)); Spacer() }
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .buttonStyle(FlowPressStyle())
            .help("Move to Ungrouped")
            ForEach(meta.topLevelFolders) { f in
                Button(action: {
                    if let id = moveSessionID { onMoveSession(id, f.id) }
                    moveSessionID = nil
                }) {
                    HStack { Image(systemName: f.icon).frame(width: 14); Text(f.name).font(.system(size: 12)); Spacer() }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(FlowPressStyle())
                ForEach(meta.subfolders(of: f.id)) { sub in
                    Button(action: {
                        if let id = moveSessionID { onMoveSession(id, sub.id) }
                        moveSessionID = nil
                    }) {
                        HStack { Image(systemName: sub.icon).frame(width: 14); Text("\(f.name) / \(sub.name)").font(.system(size: 12)); Spacer() }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .padding(.leading, 12)
                    }
                    .buttonStyle(FlowPressStyle())
                }
            }
            Divider()
            Button(action: {
                if let id = moveSessionID, let f = meta.createFolder() { onMoveSession(id, f.id) }
                moveSessionID = nil
            }) {
                HStack { Image(systemName: "folder.badge.plus").frame(width: 14); Text("New folder…").font(.system(size: 12)); Spacer() }
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            .buttonStyle(FlowPressStyle())
            .help("Create a folder and move here")
        }
        .padding(12)
        .frame(width: 240)
    }

    // MARK: - Renames / deletes

    private func startRenameSession(_ s: StepSession) {
        renamingSessionID = s.id
        renameText = s.title
    }

    private func commitRename(_ s: StepSession) {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { onRenameSession(s.id, title) }
        renamingSessionID = nil
    }

    /// Header + action: creates the folder in the shared store and drops
    /// straight into rename focus. Esc (cancel) or an empty commit removes
    /// the placeholder so "New folder" never persists.
    private func createAndRenameFolder() {
        withMotion {
            if let f = meta.createFolder() {
                pendingNewFolderID = f.id
                renamingFolderID = f.id
                folderRenameText = f.name
            }
        }
    }

    private func commitFolderRename(_ folder: FlowFolder) {
        let title = folderRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            // Empty revert: fresh placeholders are removed, existing names kept.
            if pendingNewFolderID == folder.id {
                withMotion { _ = meta.deleteFolder(folder.id) }
            }
        } else {
            meta.renameFolder(folder.id, to: title)
        }
        if pendingNewFolderID == folder.id { pendingNewFolderID = nil }
        renamingFolderID = nil
    }

    private func cancelFolderRename(_ folder: FlowFolder) {
        // Esc on a just-created folder cancels the creation entirely.
        if pendingNewFolderID == folder.id {
            withMotion { _ = meta.deleteFolder(folder.id) }
            pendingNewFolderID = nil
        }
        renamingFolderID = nil
    }

    private func confirmDeleteFolder() {
        guard let id = pendingDeleteFolderID else { return }
        withMotion { folderUndo = meta.deleteFolder(id) }
        if focusedFolderID == id { focusedFolderID = nil }
        pendingDeleteFolderID = nil
    }

    private func confirmDeleteSession() {
        guard let id = pendingDeleteSessionID else { return }
        onDeleteSession(id)
        pendingDeleteSessionID = nil
    }

    // MARK: - Keyboard

    private func withMotion(_ work: () -> Void) {
        if reduceMotion { work() } else { withAnimation(FlowMotion.standardFast) { work() } }
    }

    /// Single key handler (one `onKeyPress` keeps the type-checker fast).
    /// Up/Down move guide selection, Left/Right collapse/expand, Enter/F2
    /// rename, Delete confirms delete, M opens Move-to.
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: return moveSelection(by: -1)
        case .downArrow: return moveSelection(by: 1)
        case .leftArrow: return collapseFocused()
        case .rightArrow: return expandFocused()
        case .return: return keyboardRename()
        case .delete: return keyboardDelete()
        default:
            // F2 arrives as the private-use NSF2FunctionKey scalar (U+F702).
            if press.key.character == Character(UnicodeScalar(0xF702)!) { return keyboardRename() }
            if press.key.character == "m" || press.key.character == "M" { return keyboardMove() }
            return .ignored
        }
    }

    private func moveSelection(by delta: Int) -> KeyPress.Result {
        let order = keyboardOrder
        guard !order.isEmpty else { return .ignored }
        let current = order.firstIndex(of: session.id) ?? (delta > 0 ? -1 : order.count)
        let next = min(max(0, current + delta), order.count - 1)
        guard order.indices.contains(next) else { return .ignored }
        if let s = sessions.first(where: { $0.id == order[next] }) {
            smart = nil
            if s.id == session.id { onSelectView(.editor) } else { onSelectSession(s) }
        }
        return .handled
    }

    private func expandFocused() -> KeyPress.Result {
        if let fid = focusedFolderID ?? meta.sessionFolder[session.id] {
            withMotion { meta.setCollapsed(fid, collapsed: false) }
            return .handled
        }
        return .ignored
    }

    private func collapseFocused() -> KeyPress.Result {
        if let fid = focusedFolderID ?? meta.sessionFolder[session.id] {
            withMotion { meta.setCollapsed(fid, collapsed: true) }
            return .handled
        }
        return .ignored
    }

    private func keyboardRename() -> KeyPress.Result {
        if let fid = focusedFolderID ?? renamingFolderID,
           let f = meta.folders.first(where: { $0.id == fid }) {
            renamingFolderID = f.id
            folderRenameText = f.name
            return .handled
        }
        if let s = sessions.first(where: { $0.id == session.id }) {
            startRenameSession(s)
            return .handled
        }
        return .ignored
    }

    private func keyboardDelete() -> KeyPress.Result {
        pendingDeleteSessionID = session.id
        return .handled
    }

    private func keyboardMove() -> KeyPress.Result {
        moveSessionID = session.id
        return .handled
    }

    // MARK: - Misc helpers

    private var headerFontSize: CGFloat { contrast == .increased ? 11 : 10 }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: headerFontSize, weight: .semibold))
                .foregroundColor(FlowComponent.for(scheme).textTertiary)
            if let count {
                CountPill("\(count)")
            }
        }
        .frame(minHeight: 22)
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(title), \(count.map { "\($0) items" } ?? "")")
    }

    private func folderPath(for sessionID: String) -> String? {
        guard let fid = meta.sessionFolder[sessionID],
              let f = meta.folders.first(where: { $0.id == fid }) else { return nil }
        if let pid = f.parentID, let parent = meta.folders.first(where: { $0.id == pid }) {
            return "\(parent.name) / \(f.name)"
        }
        return f.name
    }
}

public enum FlowlineEditorView {
    case library, editor
}

/// Inline rename field: autofocus + select-all, Enter commits, Esc cancels.
private struct RenameField: View {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($focused)
            .onAppear {
                focused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil)
                }
            }
            .onSubmit { onCommit() }
            .onExitCommand { onCancel() }
    }
}

/// Small count pill — component tokens only.
private struct CountPill: View {
    var text: String
    @Environment(\.colorScheme) private var scheme
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(FlowComponent.for(scheme).textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(FlowComponent.for(scheme).surfaceSubtle)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}

/// Sidebar row (§17): transparent → surfaceSubtle on hover → accentSubtle +
/// accent text when selected. Focus ring (keyboard) stays distinct from
/// selection. Hover and selection animate via FlowMotion unless Reduce Motion.
private struct SideRow<Content: View>: View {
    var selected: Bool
    var focused: Bool = false
    var hoverID: Binding<String?>
    var id: String
    var height: CGFloat = 28
    var action: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        let hovering = hoverID.wrappedValue == id
        let anim: Animation? = reduceMotion ? nil : FlowMotion.standardFast
        return Button(action: action) {
            content()
                .foregroundColor(selected ? sem.accentDefault : t.sideFg)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minHeight: height, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? t.sideBgSelected : (hovering ? t.sideBgHover : t.sideBg))
                .cornerRadius(FlowComponent.radiusSM)
                .overlay(
                    RoundedRectangle(cornerRadius: FlowComponent.radiusSM)
                        .stroke(focused ? sem.focusRing : Color.clear, lineWidth: focused ? 2 : 0)
                )
                .animation(anim, value: selected)
                .animation(anim, value: hovering)
        }
        .buttonStyle(FlowPressStyle())
        .onHover { hoverID.wrappedValue = $0 ? id : nil }
    }
}
