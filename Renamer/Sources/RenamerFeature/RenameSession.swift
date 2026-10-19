import Foundation
import RenamerCore

enum PreviewSortKey: String, CaseIterable, Identifiable {
    case oldName, newName, status

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oldName: return "Stara nazwa"
        case .newName: return "Nowa nazwa"
        case .status: return "Status"
        }
    }
}

struct SuccessBanner: Equatable {
    let count: Int
}

struct FailureLine: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let message: String
}

struct FailureReport: Identifiable, Equatable {
    let id = UUID()
    let successCount: Int
    let failures: [FailureLine]
}

@MainActor
public final class RenameSession: ObservableObject {
    @Published var items: [FileItem] = []
    @Published var template: String = ""
    @Published var search: String = ""
    @Published var replacement: String = ""
    @Published var isRegex: Bool = false
    @Published var caseSensitive: Bool = true
    @Published var nameCase: CaseMode = .none
    @Published var extCase: CaseMode = .none
    @Published var stripDiacritics: Bool = false
    @Published var lockExtension: Bool = true
    @Published var presets: [Preset] = []
    @Published var selectedPresetID: UUID?
    /// The current plan, already sorted for display.
    @Published var rows: [RenameRow] = [] {
        didSet { recount() }
    }
    @Published var statusMessage: String = "Dodaj pliki, aby rozpocząć"
    @Published var sortKey: PreviewSortKey = .oldName
    @Published var sortAscending: Bool = true
    @Published var isApplying: Bool = false
    @Published var canUndo: Bool = false
    @Published var showOverwriteAlert: Bool = false
    @Published var successBanner: SuccessBanner?
    @Published var failureReport: FailureReport?

    private let settings: SettingsStore
    private let presetStore: PresetStore
    private var undoBatch: UndoBatch?
    private var debounceTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var addTask: Task<Void, Never>?
    /// Bumped by removeAll() so adds still loading are dropped.
    private var addGeneration = 0
    /// Number of existing files the user agreed to overwrite in the last alert.
    private var confirmedOverwriteCount = 0

    // Counted once per plan, not on every render.
    private(set) var errorCount = 0
    private(set) var warningCount = 0
    private var readyCount = 0
    var canApply: Bool { !items.isEmpty && errorCount == 0 && !isApplying }

    public init(defaults: UserDefaults = .standard) {
        settings = SettingsStore(defaults: defaults)
        presetStore = PresetStore(defaults: defaults)
        loadSettings()
        presets = presetStore.load()
        rebuildPlan()
    }

    func loadSettings() {
        let s = settings.load()
        template = s.template
        search = s.search
        replacement = s.replacement
        isRegex = s.isRegex
        caseSensitive = s.caseSensitive
        nameCase = s.nameCase
        extCase = s.extCase
        stripDiacritics = s.stripDiacritics
        lockExtension = s.lockExtension
    }

    func persistSettings() {
        settings.save(SettingsStore.Snapshot(
            template: template,
            search: search,
            replacement: replacement,
            isRegex: isRegex,
            caseSensitive: caseSensitive,
            nameCase: nameCase,
            extCase: extCase,
            stripDiacritics: stripDiacritics,
            lockExtension: lockExtension
        ))
    }

    func onConfigChanged() {
        persistSettings()
        rebuildPlan()
    }

    /// Adds files exactly as a drop onto the drop zone does (directories ignored, duplicates skipped).
    public func add(urls: [URL]) {
        addURLsNow(urls)
    }

    /// URLs of the files in the session, in the order they were added.
    public var fileURLs: [URL] { items.map(\.url) }

    /// Number of rows in the rename preview (filled shortly after files or rules change).
    public var previewRowCount: Int { rows.count }

    /// Applies a saved preset by id; returns false when there is no such preset.
    @discardableResult
    public func applyPreset(id: UUID) -> Bool {
        presets = presetStore.load()   // another window may have saved it
        guard let preset = presets.first(where: { $0.id == id }) else { return false }
        applyPreset(preset)
        return true
    }

    /// Drop / open-panel entry point: the disk reads run off the main actor (a slow or
    /// network volume must not freeze the hub). Batches are appended in arrival order.
    func addURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let previous = addTask
        let generation = addGeneration
        addTask = Task { [weak self] in
            await previous?.value
            let loaded = await Self.offMain { Self.loadFiles(urls) }
            guard let self, self.addGeneration == generation else { return }   // list cleared meanwhile
            self.append(loaded)
        }
    }

    /// Synchronous variant behind the public `add(urls:)` (hosts expect `fileURLs` to be
    /// filled on return; it is called once per window with the files it was opened with).
    private func addURLsNow(_ urls: [URL]) {
        append(Self.loadFiles(urls))
    }

    /// Reads the existing regular files among `urls` (directories and missing files skipped).
    private nonisolated static func loadFiles(_ urls: [URL]) -> [FileItem] {
        urls.compactMap { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  !isDir.boolValue else { return nil }
            return try? FileItemLoader.load(url)
        }
    }

    private func append(_ loaded: [FileItem]) {
        var seen = Set(items.map(\.url.path))
        var added: [FileItem] = []
        for item in loaded where !seen.contains(item.url.path) {
            seen.insert(item.url.path)
            added.append(item)
        }
        guard !added.isEmpty else { return }
        items.append(contentsOf: added)
        rebuildPlan()
    }

    func removeAll() {
        debounceTask?.cancel()
        addGeneration += 1
        items = []
        rows = []
        statusMessage = "Dodaj pliki, aby rozpocząć"
    }

    func toggleSort(_ key: PreviewSortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
        rebuildPlan()
    }

    /// Appends a token to a config text field. The field's TextField `.onChange`
    /// handler fires for programmatic edits too and already persists + rebuilds,
    /// so we deliberately do NOT call onConfigChanged() here (avoids doing it twice).
    func insertToken(_ token: String, into field: ReferenceWritableKeyPath<RenameSession, String>) {
        self[keyPath: field] += token
    }

    var currentConfig: RenameConfig {
        RenameConfig(
            template: template,
            find: FindReplace(search: search, replacement: replacement, isRegex: isRegex, caseSensitive: caseSensitive),
            nameCase: nameCase, extCase: extCase, stripDiacritics: stripDiacritics, lockExtension: lockExtension)
    }

    func loadConfig(_ config: RenameConfig) {
        template = config.template
        search = config.find.search
        replacement = config.find.replacement
        isRegex = config.find.isRegex
        caseSensitive = config.find.caseSensitive
        nameCase = config.nameCase
        extCase = config.extCase
        stripDiacritics = config.stripDiacritics
        lockExtension = config.lockExtension
        onConfigChanged()
    }

    func applyPreset(_ preset: Preset) {
        loadConfig(preset.config)
        selectedPresetID = preset.id
    }

    func saveCurrentAsPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = Preset(name: trimmed, config: currentConfig)
        // Load -> modify -> save: other windows share the store, never overwrite their presets.
        presets = PresetManager.add(preset, to: presetStore.load())
        presetStore.save(presets)
        selectedPresetID = preset.id
    }

    func deletePreset(id: UUID) {
        presets = PresetManager.delete(id: id, from: presetStore.load())
        presetStore.save(presets)
        if selectedPresetID == id { selectedPresetID = nil }
    }

    func renamePreset(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets = PresetManager.rename(id: id, to: trimmed, in: presetStore.load())
        presetStore.save(presets)
    }

    func requestApply() {
        startApply(overwrite: false)
    }

    func apply(overwrite: Bool) {
        startApply(overwrite: overwrite)
    }

    /// Replans with the current settings (never a stale, debounced plan), asks before
    /// overwriting, then renames off the main actor. `isApplying` stays true throughout,
    /// which also blocks a second apply or an undo until this one finishes.
    private func startApply(overwrite: Bool) {
        guard canApply else { return }
        isApplying = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isApplying = false }
            guard let planned = await self.rebuildPlanForApply() else { return }
            // Existing files are overwritten only after the user confirmed (at least) that many.
            if self.warningCount > 0, !overwrite || self.warningCount > self.confirmedOverwriteCount {
                self.confirmedOverwriteCount = self.warningCount
                self.showOverwriteAlert = true
                return
            }
            self.confirmedOverwriteCount = 0
            await self.perform(planned, overwrite: overwrite && self.warningCount > 0)
        }
    }

    /// Cancels the pending debounced rebuild and plans now. Returns nil when the fresh
    /// plan cannot be applied (no files or errors).
    private func rebuildPlanForApply() async -> [RenameRow]? {
        debounceTask?.cancel()
        debounceTask = nil
        await rebuildPlanNow()
        guard !items.isEmpty, errorCount == 0 else { return nil }
        return rows
    }

    private struct ApplyOutcome: Sendable {
        var failures: [MoveFailure] = []
        var succeeded: [Move] = []
        var undo: UndoBatch?
        /// Renamed items reloaded from their new names, keyed by their old URL.
        var renamed: [URL: FileItem] = [:]
        var error: String?
    }

    private func perform(_ planned: [RenameRow], overwrite: Bool) async {
        let outcome = await Self.offMain { () -> ApplyOutcome in
            do {
                let result = try RenameEngine().apply(rows: planned, overwrite: overwrite)
                var outcome = ApplyOutcome(failures: result.failures,
                                           succeeded: result.successfulRenames,
                                           undo: result.undo)
                for move in result.successfulRenames {
                    let date = planned.first { $0.item.url == move.from }?.item.modificationDate
                    outcome.renamed[move.from] = (try? FileItemLoader.load(move.to))
                        ?? FileItem(url: move.to, modificationDate: date ?? Date(timeIntervalSince1970: 0))
                }
                return outcome
            } catch {
                return ApplyOutcome(error: error.localizedDescription)
            }
        }

        if let error = outcome.error {
            dismissBanner()
            failureReport = FailureReport(successCount: 0,
                                          failures: [FailureLine(name: "—", message: error)])
            statusMessage = "Błąd: \(error)"
            return
        }

        // Follow renamed files to their new names; failed ones keep their old URLs.
        items = items.map { outcome.renamed[$0.url] ?? $0 }
        undoBatch = outcome.undo.flatMap { $0.isEmpty ? nil : $0 }
        canUndo = undoBatch != nil
        let succeeded = outcome.succeeded.count
        if outcome.failures.isEmpty {
            statusMessage = "Zmienione pliki: \(succeeded)"
            showSuccessBanner(count: succeeded)
        } else {
            dismissBanner()
            let lines = outcome.failures.map {
                FailureLine(name: $0.move.from.lastPathComponent, message: $0.message)
            }
            failureReport = FailureReport(successCount: succeeded, failures: lines)
            statusMessage = "Błędy: \(outcome.failures.count)"
        }
        rebuildPlan()
    }

    private func showSuccessBanner(count: Int) {
        bannerTask?.cancel()
        successBanner = SuccessBanner(count: count)
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.successBanner = nil
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        successBanner = nil
    }

    private struct UndoResult: Sendable {
        let outcome: UndoOutcome
        /// Restored items reloaded from their old names, keyed by the URL they had before undo.
        let restored: [URL: FileItem]
    }

    /// Best-effort undo off the main actor. Files that went back are dropped from the
    /// batch; anything left can be retried with another undo.
    func undoLast() {
        guard let batch = undoBatch, !isApplying else { return }
        isApplying = true
        Task { [weak self] in
            let result = await Self.offMain { () -> UndoResult in
                let outcome = batch.undo()
                var restored: [URL: FileItem] = [:]
                for move in outcome.restored {
                    restored[move.from] = (try? FileItemLoader.load(move.to))
                        ?? FileItem(url: move.to, modificationDate: Date(timeIntervalSince1970: 0))
                }
                return UndoResult(outcome: outcome, restored: restored)
            }
            guard let self else { return }
            self.isApplying = false
            self.items = self.items.map { result.restored[$0.url] ?? $0 }
            self.undoBatch = result.outcome.remaining.isEmpty ? nil : result.outcome.remaining
            self.canUndo = self.undoBatch != nil
            self.dismissBanner()
            let failures = result.outcome.failures
            if failures.isEmpty {
                self.statusMessage = "Cofnięto ostatnią operację."
            } else {
                self.failureReport = FailureReport(
                    successCount: result.outcome.restored.count,
                    failures: failures.map { FailureLine(name: $0.move.from.lastPathComponent, message: $0.message) })
                self.statusMessage = "Cofnięcie nie powiodło się dla plików: \(failures.count)"
            }
            self.rebuildPlan()
        }
    }

    /// Rows in display order (`rows` is kept sorted).
    func displayedRows() -> [RenameRow] {
        rows
    }

    private func rebuildPlan() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.rebuildPlanNow()
        }
    }

    /// Plans off the main actor: a slow template or a runaway regex must not freeze the
    /// hub. Cancelling the calling task (a newer edit) abandons the result.
    private func rebuildPlanNow() async {
        guard !items.isEmpty else {
            rows = []
            statusMessage = "Dodaj pliki, aby rozpocząć"
            return
        }

        let config = currentConfig
        let items = items
        let sortKey = sortKey
        let ascending = sortAscending
        let planned = await Self.offMain { () -> [RenameRow] in
            let sorted = Self.sortedItems(items, ascending: ascending)
            return Self.sortedRows(RenameEngine().plan(items: sorted, config: config),
                                   by: sortKey, ascending: ascending)
        }
        guard !Task.isCancelled else { return }
        rows = planned
        updateStatusMessage()
    }

    /// Runs blocking work (disk IO, planning) off the main actor. Cancelling the caller
    /// cancels the work too (it sees `Task.isCancelled`).
    private nonisolated static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        let task = Task.detached(priority: .userInitiated, operation: work)
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func sortedItems(_ source: [FileItem], ascending: Bool) -> [FileItem] {
        source.sorted { a, b in
            let cmp = a.fullName.localizedStandardCompare(b.fullName)
            return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }

    private nonisolated static func sortedRows(_ source: [RenameRow], by sortKey: PreviewSortKey,
                                               ascending: Bool) -> [RenameRow] {
        source.sorted { a, b in
            let cmp: ComparisonResult
            switch sortKey {
            case .oldName:
                cmp = a.item.fullName.localizedStandardCompare(b.item.fullName)
            case .newName:
                cmp = a.proposedName.localizedStandardCompare(b.proposedName)
            case .status:
                cmp = statusRank(a.status).localizedStandardCompare(statusRank(b.status))
            }
            return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }

    private nonisolated static func statusRank(_ status: RowStatus) -> String {
        switch status {
        case .error: return "0"
        case .warning: return "1"
        case .ok: return "2"
        }
    }

    private func recount() {
        var errors = 0, warnings = 0, ready = 0
        for row in rows {
            switch row.status {
            case .error: errors += 1
            case .warning: warnings += 1
            case .ok: ready += 1
            }
        }
        errorCount = errors
        warningCount = warnings
        readyCount = ready
    }

    private func updateStatusMessage() {
        var parts = ["Pliki: \(items.count)", "Gotowe: \(readyCount)"]
        if errorCount > 0 { parts.append("Błędy: \(errorCount)") }
        if warningCount > 0 { parts.append("Ostrzeżenia: \(warningCount)") }
        statusMessage = parts.joined(separator: " · ")
    }
}
