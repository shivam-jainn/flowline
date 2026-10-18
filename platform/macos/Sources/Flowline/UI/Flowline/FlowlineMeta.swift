import SwiftUI
import FlowlineIR
import FlowlinePublishing

// MARK: - UI-only per-step metadata (annotations, comments, halo override)
//
// The IR `Step` is frozen by shared contracts + golden corpora, so editor
// affordances the prototype carries (annotation chips, comments, applied
// Halo kinds) live in this app-surface store, keyed by session/step id and
// persisted to UserDefaults. No portable module is touched.

public struct FlowStepComment: Codable, Equatable {
    public var who: String
    public var text: String
    public init(who: String, text: String) { self.who = who; self.text = text }
}

public struct FlowStepMeta: Codable, Equatable {
    public var annotations: [String] = []
    public var comments: [FlowStepComment] = []
    /// Applied Halo kind override (nil = auto from interaction target).
    public var haloKind: FlowlineHaloKind? = nil
    public init() {}
}

// MARK: - UI-only guide style (media treatment, numbering, accent)

public enum FlowMediaTreatment: String, Codable, CaseIterable {
    case full, rounded, framed
    public var label: String {
        switch self { case .full: return "Full frame"; case .rounded: return "Rounded"; case .framed: return "Framed" }
    }
}

public enum FlowNumbering: String, Codable, CaseIterable {
    case numeric, checkbox, none
    public var label: String {
        switch self { case .numeric: return "Numeric"; case .checkbox: return "Checkboxes"; case .none: return "None" }
    }
}

public struct FlowGuideStyle: Codable, Equatable {
    public var media: FlowMediaTreatment = .rounded
    public var numbering: FlowNumbering = .numeric
    public var accent: FlowAccentChoice = .blue
    public var autoHalo: Bool = true
    public var defaultHalo: FlowlineHaloKind = .click
    /// Selectable keystroke + pointer visuals (style panel + stage + export).
    public var keycapStyle: KeycapStyle = .mac3D
    public var mouseStyle: MouseStyle = .mac3D
    public init() {}

    private enum Keys: String, CodingKey {
        case media, numbering, accent, autoHalo, defaultHalo
        case keycapStyle, mouseStyle
    }

    /// Tolerant decode: pre-style UserDefaults payloads lack the new keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        media = try c.decodeIfPresent(FlowMediaTreatment.self, forKey: .media) ?? .rounded
        numbering = try c.decodeIfPresent(FlowNumbering.self, forKey: .numbering) ?? .numeric
        accent = try c.decodeIfPresent(FlowAccentChoice.self, forKey: .accent) ?? .blue
        autoHalo = try c.decodeIfPresent(Bool.self, forKey: .autoHalo) ?? true
        defaultHalo = try c.decodeIfPresent(FlowlineHaloKind.self, forKey: .defaultHalo) ?? .click
        keycapStyle = try c.decodeIfPresent(KeycapStyle.self, forKey: .keycapStyle) ?? .mac3D
        mouseStyle = try c.decodeIfPresent(MouseStyle.self, forKey: .mouseStyle) ?? .mac3D
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(media, forKey: .media)
        try c.encode(numbering, forKey: .numbering)
        try c.encode(accent, forKey: .accent)
        try c.encode(autoHalo, forKey: .autoHalo)
        try c.encode(defaultHalo, forKey: .defaultHalo)
        try c.encode(keycapStyle, forKey: .keycapStyle)
        try c.encode(mouseStyle, forKey: .mouseStyle)
    }
}

// MARK: - Workspace folders (user-assigned org, §17)
//
// Two-level max: L0 folders (`parentID == nil`), L1 subfolders
// (`parentID` = L0 id), L2 guides only. L3 is blocked by `createFolder`
// refusing a parent that already has a parent.

public struct FlowFolder: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var parentID: String?
    public var icon: String
    public init(
        id: String = UUID().uuidString,
        name: String,
        colorHex: String = FlowPrimitive.UserFolder.defaultHex,
        parentID: String? = nil,
        icon: String = "folder"
    ) {
        self.id = id; self.name = name; self.colorHex = colorHex
        self.parentID = parentID; self.icon = icon
    }

    private enum Keys: String, CodingKey {
        case id, name, colorHex, parentID, icon
    }

    /// Tolerant decode: old v1 payloads lack `parentID`/`icon`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "folder"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(parentID, forKey: .parentID)
        try c.encode(icon, forKey: .icon)
    }

    public func color(for scheme: ColorScheme) -> Color {
        FlowSemantic.for(scheme).folderColor(hex: colorHex)
    }
}

// MARK: - Store

/// Observable UI-only metadata. Owned by `FlowlineEditor` as a `@StateObject`
/// and passed down; persists to UserDefaults under a versioned key.
public final class FlowlineMetaStore: ObservableObject {
    private static let key = "flowline.meta.v1"
    public static let minSidebarWidth: Double = 180
    public static let maxSidebarWidth: Double = 320
    public static let defaultSidebarWidth: Double = 236

    @Published public var steps: [String: FlowStepMeta] = [:]   // "\(sessionID)/\(stepID)"
    @Published public var guides: [String: FlowGuideStyle] = [:] // sessionID
    @Published public var folders: [FlowFolder] = []
    @Published public var sessionFolder: [String: String] = [:]  // sessionID -> folderID
    @Published public var favoriteSessionIDs: Set<String> = []
    @Published public var collapsedFolderIDs: Set<String> = []
    @Published public var sidebarWidth: Double = FlowlineMetaStore.defaultSidebarWidth

    public init() { load() }

    // MARK: steps

    private func stepKey(sessionID: String, stepID: String) -> String { "\(sessionID)/\(stepID)" }

    public func meta(sessionID: String, stepID: String) -> FlowStepMeta {
        steps[stepKey(sessionID: sessionID, stepID: stepID)] ?? FlowStepMeta()
    }

    public func updateStep(sessionID: String, stepID: String, _ mutate: (inout FlowStepMeta) -> Void) {
        let k = stepKey(sessionID: sessionID, stepID: stepID)
        var m = steps[k] ?? FlowStepMeta()
        mutate(&m)
        steps[k] = m
        save()
    }

    public func haloKind(for step: Step, sessionID: String, fallback: FlowlineHaloKind?) -> FlowlineHaloKind? {
        if let o = steps[stepKey(sessionID: sessionID, stepID: step.id)]?.haloKind { return o }
        return fallback
    }

    /// Explicit applied override, if any (nil = auto). Used by the stage
    /// visibility gate so applied halos stay visible when Auto Halo is off.
    public func appliedHaloKind(sessionID: String, stepID: String) -> FlowlineHaloKind? {
        steps[stepKey(sessionID: sessionID, stepID: stepID)]?.haloKind
    }

    /// Copy per-step meta (halo override, annotations, comments) from one
    /// step id to another (duplicate / split). No-op when source has no entry.
    public func copyStepMeta(sessionID: String, fromID: String, toID: String) {
        let from = stepKey(sessionID: sessionID, stepID: fromID)
        guard let m = steps[from] else { return }
        steps[stepKey(sessionID: sessionID, stepID: toID)] = m
        save()
    }

    /// Remove orphaned per-step entries (delete / merge). Keeps UserDefaults
    /// from accumulating keys for steps that no longer exist.
    public func removeSteps(sessionID: String, ids: [String]) {
        for id in ids { steps.removeValue(forKey: stepKey(sessionID: sessionID, stepID: id)) }
        save()
    }

    /// Whole-dict snapshot / restore for editor undo-redo pairing.
    /// `FlowlineHistory` only snapshots `[Step]`, so the editor keeps a
    /// parallel stack of these dicts to keep meta in sync on undo/redo.
    public func stepsSnapshot() -> [String: FlowStepMeta] { steps }
    public func restoreSteps(_ snapshot: [String: FlowStepMeta]) {
        steps = snapshot
        save()
    }

    // MARK: guides

    public func style(sessionID: String) -> FlowGuideStyle {
        // No per-guide override yet → start from the onboarding defaults
        // (Settings → Onboarding), not the factory FlowGuideStyle().
        guides[sessionID] ?? OnboardingDefaultsStore.load().guideStyle()
    }

    public func updateGuide(sessionID: String, _ mutate: (inout FlowGuideStyle) -> Void) {
        var g = guides[sessionID] ?? OnboardingDefaultsStore.load().guideStyle()
        mutate(&g)
        guides[sessionID] = g
        save()
    }

    // MARK: favorites (Smart Groups source)

    public func isFavorite(_ sessionID: String) -> Bool {
        favoriteSessionIDs.contains(sessionID)
    }

    public func setFavorite(_ sessionID: String, _ favorite: Bool) {
        if favorite { favoriteSessionIDs.insert(sessionID) }
        else { favoriteSessionIDs.remove(sessionID) }
        save()
    }

    public func toggleFavorite(_ sessionID: String) {
        if favoriteSessionIDs.contains(sessionID) { favoriteSessionIDs.remove(sessionID) }
        else { favoriteSessionIDs.insert(sessionID) }
        save()
    }

    // MARK: sidebar width (resizable 180–320, default 236)

    public func setSidebarWidth(_ width: Double) {
        sidebarWidth = min(FlowlineMetaStore.maxSidebarWidth, max(FlowlineMetaStore.minSidebarWidth, width))
        save()
    }

    // MARK: collapse (persisted; replaces local @State)

    public func isCollapsed(_ folderID: String) -> Bool {
        collapsedFolderIDs.contains(folderID)
    }

    public func setCollapsed(_ folderID: String, collapsed: Bool) {
        if collapsed { collapsedFolderIDs.insert(folderID) }
        else { collapsedFolderIDs.remove(folderID) }
        save()
    }

    public func toggleCollapsed(_ folderID: String) {
        if collapsedFolderIDs.contains(folderID) { collapsedFolderIDs.remove(folderID) }
        else { collapsedFolderIDs.insert(folderID) }
        save()
    }

    public func collapseAll() {
        collapsedFolderIDs = Set(folders.map { $0.id })
        save()
    }

    public func expandAll() {
        collapsedFolderIDs.removeAll()
        save()
    }

    // MARK: folders (2-level max)

    public var topLevelFolders: [FlowFolder] {
        folders.filter { $0.parentID == nil }
    }

    public func subfolders(of folderID: String) -> [FlowFolder] {
        folders.filter { $0.parentID == folderID }
    }

    public func depth(of folder: FlowFolder) -> Int {
        guard let pid = folder.parentID else { return 0 }
        guard folders.contains(where: { $0.id == pid }) else { return 0 }
        return 1
    }

    /// Create a folder; `parentID` must be an L0 folder (L3 blocked by
    /// returning nil when the parent already has a parent).
    @discardableResult
    public func createFolder(name: String = "New folder", parentID: String? = nil) -> FlowFolder? {
        if let pid = parentID {
            guard let parent = folders.first(where: { $0.id == pid }),
                  parent.parentID == nil else { return nil }
        }
        let f = FlowFolder(name: name, parentID: parentID)
        folders.append(f)
        save()
        return f
    }

    public func renameFolder(_ id: String, to name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = title
        save()
    }

    public func setFolderColor(_ id: String, hex: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].colorHex = hex
        save()
    }

    public func setFolderIcon(_ id: String, icon: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].icon = icon
        save()
    }

    public struct FolderBackup: Equatable {
        public var folders: [FlowFolder]
        public var sessionFolder: [String: String]
        public var collapsed: Set<String>
    }

    public func foldersSnapshot() -> FolderBackup {
        FolderBackup(folders: folders, sessionFolder: sessionFolder, collapsed: collapsedFolderIDs)
    }

    public func restoreFolders(_ backup: FolderBackup) {
        folders = backup.folders
        sessionFolder = backup.sessionFolder
        collapsedFolderIDs = backup.collapsed
        save()
    }

    /// Delete a folder + its L1 subfolders; contained guides become Ungrouped.
    /// Returns a backup for undo-toast restore.
    @discardableResult
    public func deleteFolder(_ id: String) -> FolderBackup {
        let backup = foldersSnapshot()
        var doomed: Set<String> = [id]
        for f in folders where f.parentID == id { doomed.insert(f.id) }
        folders.removeAll(where: { doomed.contains($0.id) })
        for (sid, fid) in sessionFolder where doomed.contains(fid) {
            sessionFolder[sid] = nil
        }
        collapsedFolderIDs.subtract(doomed)
        save()
        return backup
    }

    public func folder(for sessionID: String) -> FlowFolder? {
        guard let fid = sessionFolder[sessionID] else { return nil }
        return folders.first(where: { $0.id == fid })
    }

    public func move(sessionID: String, to folderID: String?) {
        if let fid = folderID {
            guard folders.contains(where: { $0.id == fid }) else { return }
            sessionFolder[sessionID] = fid
        } else {
            sessionFolder[sessionID] = nil
        }
        save()
    }

    // MARK: persistence

    private struct Snapshot: Codable {
        var steps: [String: FlowStepMeta]
        var guides: [String: FlowGuideStyle]
        var folders: [FlowFolder]
        var sessionFolder: [String: String]
        var favoriteSessionIDs: Set<String>
        var collapsedFolderIDs: Set<String>
        var sidebarWidth: Double

        init(
            steps: [String: FlowStepMeta] = [:],
            guides: [String: FlowGuideStyle] = [:],
            folders: [FlowFolder] = [],
            sessionFolder: [String: String] = [:],
            favoriteSessionIDs: Set<String> = [],
            collapsedFolderIDs: Set<String> = [],
            sidebarWidth: Double = FlowlineMetaStore.defaultSidebarWidth
        ) {
            self.steps = steps; self.guides = guides; self.folders = folders
            self.sessionFolder = sessionFolder
            self.favoriteSessionIDs = favoriteSessionIDs
            self.collapsedFolderIDs = collapsedFolderIDs
            self.sidebarWidth = sidebarWidth
        }

        private enum Keys: String, CodingKey {
            case steps, guides, folders, sessionFolder
            case favoriteSessionIDs, collapsedFolderIDs, sidebarWidth
        }

        /// Tolerant decode: old v1 payloads carry only the first four keys.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            steps = try c.decodeIfPresent([String: FlowStepMeta].self, forKey: .steps) ?? [:]
            guides = try c.decodeIfPresent([String: FlowGuideStyle].self, forKey: .guides) ?? [:]
            folders = try c.decodeIfPresent([FlowFolder].self, forKey: .folders) ?? []
            sessionFolder = try c.decodeIfPresent([String: String].self, forKey: .sessionFolder) ?? [:]
            favoriteSessionIDs = try c.decodeIfPresent(Set<String>.self, forKey: .favoriteSessionIDs) ?? []
            collapsedFolderIDs = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedFolderIDs) ?? []
            sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? FlowlineMetaStore.defaultSidebarWidth
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(steps, forKey: .steps)
            try c.encode(guides, forKey: .guides)
            try c.encode(folders, forKey: .folders)
            try c.encode(sessionFolder, forKey: .sessionFolder)
            try c.encode(favoriteSessionIDs, forKey: .favoriteSessionIDs)
            try c.encode(collapsedFolderIDs, forKey: .collapsedFolderIDs)
            try c.encode(sidebarWidth, forKey: .sidebarWidth)
        }
    }

    private func load() {
        guard let d = UserDefaults.standard.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: d) else { return }
        steps = s.steps; guides = s.guides; folders = s.folders; sessionFolder = s.sessionFolder
        favoriteSessionIDs = s.favoriteSessionIDs
        collapsedFolderIDs = s.collapsedFolderIDs
        sidebarWidth = min(Self.maxSidebarWidth, max(Self.minSidebarWidth, s.sidebarWidth))
        pruneStaleIDs()
    }

    /// Drop references to folders that no longer exist (stale session maps,
    /// stale collapse ids, dangling subfolder parents demoted to L0).
    private func pruneStaleIDs() {
        let ids = Set(folders.map { $0.id })
        var pruned = false
        let staleSessions = sessionFolder.filter { !ids.contains($0.value) }.map { $0.key }
        for k in staleSessions { sessionFolder.removeValue(forKey: k); pruned = true }
        let staleCollapsed = collapsedFolderIDs.subtracting(ids)
        if !staleCollapsed.isEmpty { collapsedFolderIDs.subtract(staleCollapsed); pruned = true }
        for i in folders.indices where folders[i].parentID != nil && !ids.contains(folders[i].parentID!) {
            folders[i].parentID = nil; pruned = true
        }
        if pruned { save() }
    }

    private func save() {
        let s = Snapshot(
            steps: steps, guides: guides, folders: folders, sessionFolder: sessionFolder,
            favoriteSessionIDs: favoriteSessionIDs, collapsedFolderIDs: collapsedFolderIDs,
            sidebarWidth: sidebarWidth
        )
        if let d = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(d, forKey: Self.key)
        }
    }
}
