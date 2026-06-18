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
final class RenameSession: ObservableObject {
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
    @Published var rows: [RenameRow] = []
    @Published var statusMessage: String = "Przeciągnij pliki lub użyj \"Otwórz…\""
    @Published var sortKey: PreviewSortKey = .oldName
    @Published var sortAscending: Bool = true
    @Published var isApplying: Bool = false
    @Published var canUndo: Bool = false
    @Published var showOverwriteAlert: Bool = false
    @Published var successBanner: SuccessBanner?
    @Published var failureReport: FailureReport?

    private let engine = RenameEngine()
    private let settings = SettingsStore()
    private let presetStore = PresetStore()
    private var undoBatch: UndoBatch?
    private var debounceTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    var errorCount: Int { rows.filter { $0.status == .error }.count }
    var warningCount: Int { rows.filter { $0.status == .warning }.count }
    var canApply: Bool { !items.isEmpty && errorCount == 0 && !isApplying }

    init() {
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

    func addURLs(_ urls: [URL]) {
        let files = urls.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        }
        guard !files.isEmpty else { return }

        var seen = Set(items.map(\.url.path))
        var added: [FileItem] = []
        for url in files {
            guard !seen.contains(url.path), let item = try? FileItemLoader.load(url) else { continue }
            seen.insert(url.path)
            added.append(item)
        }
        guard !added.isEmpty else { return }
        items.append(contentsOf: added)
        rebuildPlan()
    }

    func removeAll() {
        items = []
        rows = []
        statusMessage = "Przeciągnij pliki lub użyj \"Otwórz…\""
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
        presets = PresetManager.add(preset, to: presets)
        presetStore.save(presets)
        selectedPresetID = preset.id
    }

    func deletePreset(id: UUID) {
        presets = PresetManager.delete(id: id, from: presets)
        presetStore.save(presets)
        if selectedPresetID == id { selectedPresetID = nil }
    }

    func renamePreset(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets = PresetManager.rename(id: id, to: trimmed, in: presets)
        presetStore.save(presets)
    }

    func requestApply() {
        guard canApply else { return }
        if warningCount > 0 {
            showOverwriteAlert = true
        } else {
            apply(overwrite: false)
        }
    }

    func apply(overwrite: Bool) {
        guard canApply else { return }
        isApplying = true
        defer { isApplying = false }

        do {
            let toApply = displayedRows().filter { $0.status != .error && $0.proposedName != $0.item.fullName }
            let result = try engine.apply(rows: displayedRows(), overwrite: overwrite)
            if result.failures.isEmpty {
                undoBatch = result.undo
                canUndo = true
                items = FileItemLoader.load(items.map(\.url))
                statusMessage = "Zmieniono \(toApply.count) plik(ów)."
                showSuccessBanner(count: toApply.count)
            } else {
                dismissBanner()
                let lines = result.failures.map {
                    FailureLine(name: $0.move.to.lastPathComponent, message: $0.message)
                }
                let succeeded = max(0, toApply.count - result.failures.count)
                failureReport = FailureReport(successCount: succeeded, failures: lines)
                statusMessage = "Błędy: \(result.failures.count)"
                undoBatch = result.undo
                canUndo = !result.undo.moves.isEmpty
                items = FileItemLoader.load(items.map(\.url))
            }
            rebuildPlan()
        } catch {
            dismissBanner()
            failureReport = FailureReport(successCount: 0,
                                          failures: [FailureLine(name: "—", message: error.localizedDescription)])
            statusMessage = "Błąd: \(error.localizedDescription)"
        }
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

    func undoLast() {
        guard let undoBatch else { return }
        do {
            try undoBatch.undo()
            self.undoBatch = nil
            canUndo = false
            dismissBanner()
            items = FileItemLoader.load(items.map(\.url))
            statusMessage = "Cofnięto ostatnią operację."
            rebuildPlan()
        } catch {
            statusMessage = "Cofnięcie nie powiodło się: \(error.localizedDescription)"
        }
    }

    func displayedRows() -> [RenameRow] {
        sortedRows(rows)
    }

    private func rebuildPlan() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            self.rebuildPlanNow()
        }
    }

    private func rebuildPlanNow() {
        guard !items.isEmpty else {
            rows = []
            statusMessage = "Przeciągnij pliki lub użyj \"Otwórz…\""
            return
        }

        let config = currentConfig
        let sorted = sortedItems(items)
        rows = sortedRows(engine.plan(items: sorted, config: config))
        updateStatusMessage()
    }

    private func sortedItems(_ source: [FileItem]) -> [FileItem] {
        source.sorted { a, b in
            let cmp = a.fullName.localizedStandardCompare(b.fullName)
            return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }

    private func sortedRows(_ source: [RenameRow]) -> [RenameRow] {
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
            return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }

    private func statusRank(_ status: RowStatus) -> String {
        switch status {
        case .error: return "0"
        case .warning: return "1"
        case .ok: return "2"
        }
    }

    private func updateStatusMessage() {
        let ready = rows.filter { $0.status == .ok }.count
        var parts = ["\(items.count) plików", "\(ready) gotowych"]
        if errorCount > 0 { parts.append("\(errorCount) błędów") }
        if warningCount > 0 { parts.append("\(warningCount) ostrzeżeń") }
        statusMessage = parts.joined(separator: " · ")
    }
}
