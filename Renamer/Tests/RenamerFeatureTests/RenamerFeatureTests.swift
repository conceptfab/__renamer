import XCTest
import RenamerCore
@testable import RenamerFeature

/// Injected `UserDefaults`, the `.standard` default, reading existing presets/settings and
/// `RenameSession.add(urls:)`. Every test uses a throw-away suite; the `.standard` test only
/// sets a volatile argument domain, so nothing is written to any real defaults domain.
@MainActor
final class RenamerFeatureTests: XCTestCase {
    private var suiteNames: [String] = []
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for name in suiteNames { UserDefaults().removePersistentDomain(forName: name) }
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        suiteNames = []
        tempDirs = []
        try await super.tearDown()
    }

    private func makeSuite() -> UserDefaults {
        let name = "dev.renamer.tests.\(UUID().uuidString)"
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenamerFeatureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func makeFiles(_ names: [String], in dir: URL) throws -> [URL] {
        try names.map { name in
            let url = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            return url
        }
    }

    private func preset(_ name: String, template: String) -> Preset {
        Preset(name: name, config: RenameConfig(
            template: template,
            find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
            nameCase: .upper, extCase: .none, stripDiacritics: false, lockExtension: true))
    }

    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    // MARK: SettingsStore

    func testSettingsStoreUsesTheInjectedDefaults() {
        let a = makeSuite()
        let b = makeSuite()
        var snapshot = SettingsStore.Snapshot()
        snapshot.template = "[N]_[C]"
        snapshot.search = "foo"
        snapshot.replacement = "bar"
        snapshot.isRegex = true
        snapshot.caseSensitive = false
        snapshot.nameCase = .title
        snapshot.lockExtension = false
        SettingsStore(defaults: a).save(snapshot)

        let loaded = SettingsStore(defaults: a).load()
        XCTAssertEqual(loaded.template, "[N]_[C]")
        XCTAssertEqual(loaded.search, "foo")
        XCTAssertEqual(loaded.replacement, "bar")
        XCTAssertTrue(loaded.isRegex)
        XCTAssertFalse(loaded.caseSensitive)
        XCTAssertEqual(loaded.nameCase, .title)
        XCTAssertFalse(loaded.lockExtension)
        XCTAssertEqual(a.string(forKey: "renamer.template"), "[N]_[C]")

        // Another suite stays untouched and loads the defaults.
        let other = SettingsStore(defaults: b).load()
        XCTAssertEqual(other.template, "")
        XCTAssertTrue(other.caseSensitive)
        XCTAssertTrue(other.lockExtension)
        XCTAssertNil(b.object(forKey: "renamer.template"))
    }

    func testSettingsStoreReadsExistingKeys() {
        let suite = makeSuite()
        // Written as the standalone Renamer.app stores them (and as the hub migrator copies them).
        suite.set("IMG_[C:3]", forKey: "renamer.template")
        suite.set("lower", forKey: "renamer.extCase")
        suite.set(true, forKey: "renamer.stripDiacritics")
        let loaded = SettingsStore(defaults: suite).load()
        XCTAssertEqual(loaded.template, "IMG_[C:3]")
        XCTAssertEqual(loaded.extCase, .lower)
        XCTAssertTrue(loaded.stripDiacritics)
    }

    /// `SettingsStore()`, `PresetStore()` and `RenameSession()` read `.standard`. Checked through
    /// a volatile argument domain (searched first by `.standard`, never written to disk).
    func testDefaultInitializersReadStandard() throws {
        let standard = UserDefaults.standard
        let argumentDomain = UserDefaults.argumentDomain
        let saved = standard.volatileDomain(forName: argumentDomain)
        defer { standard.setVolatileDomain(saved, forName: argumentDomain) }

        let stored = [preset("Zdjęcia", template: "FOTO_[C]")]
        var domain = saved
        domain["renamer.template"] = "FROM_STANDARD_[C]"
        domain["renamer.presets"] = try JSONEncoder().encode(stored)
        standard.setVolatileDomain(domain, forName: argumentDomain)

        XCTAssertEqual(SettingsStore().load().template, "FROM_STANDARD_[C]")
        XCTAssertEqual(PresetStore().load(), stored)
        let session = RenameSession()
        XCTAssertEqual(session.template, "FROM_STANDARD_[C]")
        XCTAssertEqual(session.presets, stored)
        // (Isolation of injected suites is covered by testSettingsStoreUsesTheInjectedDefaults;
        // the argument domain is shared by every UserDefaults instance, so not checked here.)
    }

    // MARK: PresetStore

    func testPresetStoreReadsExistingPresets() throws {
        let suite = makeSuite()
        let stored = [preset("A", template: "A_[C]"), preset("B", template: "B_[N]")]
        suite.set(try JSONEncoder().encode(stored), forKey: "renamer.presets")

        XCTAssertEqual(PresetStore(defaults: suite).load(), stored)
        XCTAssertEqual(RenamerPresetInfo.saved(in: suite).map(\.name), ["A", "B"])
        XCTAssertEqual(RenamerPresetInfo.saved(in: suite).map(\.id), stored.map(\.id))
    }

    func testPresetStoreRoundTripAndBadData() {
        let suite = makeSuite()
        XCTAssertEqual(PresetStore(defaults: suite).load(), [])
        let stored = [preset("C", template: "[N]")]
        PresetStore(defaults: suite).save(stored)
        XCTAssertEqual(PresetStore(defaults: suite).load(), stored)

        suite.set(Data("not json".utf8), forKey: "renamer.presets")
        XCTAssertEqual(PresetStore(defaults: suite).load(), [])
    }

    // MARK: RenameSession

    func testSessionReadsExistingSettingsAndPresets() throws {
        let suite = makeSuite()
        let stored = [preset("Skany", template: "SKAN_[C]")]
        suite.set(try JSONEncoder().encode(stored), forKey: "renamer.presets")
        suite.set("LAST_[N]", forKey: "renamer.template")

        let session = RenameSession(defaults: suite)
        XCTAssertEqual(session.template, "LAST_[N]")
        XCTAssertEqual(session.presets, stored)
    }

    func testSessionPersistsToTheInjectedSuite() throws {
        let suite = makeSuite()
        let stored = [preset("Skany", template: "SKAN_[C]")]
        suite.set(try JSONEncoder().encode(stored), forKey: "renamer.presets")
        let session = RenameSession(defaults: suite)

        XCTAssertFalse(session.applyPreset(id: UUID()))
        XCTAssertTrue(session.applyPreset(id: stored[0].id))
        XCTAssertEqual(session.template, "SKAN_[C]")
        XCTAssertEqual(session.selectedPresetID, stored[0].id)
        XCTAssertEqual(suite.string(forKey: "renamer.template"), "SKAN_[C]")
        XCTAssertEqual(suite.string(forKey: "renamer.nameCase"), "upper")

        session.saveCurrentAsPreset(name: "Nowy")
        XCTAssertEqual(PresetStore(defaults: suite).load().map(\.name).sorted(), ["Nowy", "Skany"])
    }

    func testAddURLsAddsFilesOnlyOnceAndIgnoresFoldersAndMissingFiles() async throws {
        let dir = try makeTempDir()
        let files = try makeFiles(["b.txt", "a.jpg", "c.pdf"], in: dir)
        let folder = dir.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = dir.appendingPathComponent("missing.txt")

        let session = RenameSession(defaults: makeSuite())
        session.add(urls: files + [folder, missing, files[0]])
        XCTAssertEqual(session.fileURLs.map(\.lastPathComponent), ["b.txt", "a.jpg", "c.pdf"])

        session.add(urls: files)
        XCTAssertEqual(session.fileURLs.count, 3)

        let more = try makeFiles(["d.txt"], in: dir)
        session.add(urls: more)
        XCTAssertEqual(session.fileURLs.count, 4)

        // The preview is rebuilt (debounced) for every added file.
        let previewReady = await waitFor { session.previewRowCount == 4 }
        XCTAssertTrue(previewReady)
        XCTAssertTrue(session.canApply)
    }

    func testAddURLsWithFiftyFilesBuildsThePreview() async throws {
        let dir = try makeTempDir()
        let files = try makeFiles((1...50).map { "plik-\($0).txt" }, in: dir)
        let session = RenameSession(defaults: makeSuite())
        session.add(urls: files)
        XCTAssertEqual(session.fileURLs.count, 50)
        let previewReady = await waitFor { session.previewRowCount == 50 }
        XCTAssertTrue(previewReady)
    }

    // MARK: Audit regressions

    private func names(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    }

    /// The drop/open-panel path reads the disk off the main actor and keeps arrival order.
    func testAddURLsFromDropLoadsInTheBackgroundInOrder() async throws {
        let dir = try makeTempDir()
        let first = try makeFiles(["b.txt", "a.txt"], in: dir)
        let second = try makeFiles(["c.txt"], in: dir)
        let session = RenameSession(defaults: makeSuite())
        session.addURLs(first)
        session.addURLs(second + first)
        let loaded = await waitFor { session.fileURLs.count == 3 }
        XCTAssertTrue(loaded)
        XCTAssertEqual(session.fileURLs.map(\.lastPathComponent), ["b.txt", "a.txt", "c.txt"])
    }

    /// Apply right after an edit (debounce still pending) uses the new rules, and the
    /// list then follows the files to their new names; undo brings both back.
    func testApplyUsesTheLatestRulesFollowsRenamedFilesAndUndoes() async throws {
        let dir = try makeTempDir()
        let files = try makeFiles(["a.txt", "b.txt"], in: dir)
        let session = RenameSession(defaults: makeSuite())
        session.add(urls: files)
        let planned = await waitFor { session.previewRowCount == 2 }
        XCTAssertTrue(planned)

        session.template = "{name}_new"
        session.onConfigChanged()
        session.requestApply()
        XCTAssertTrue(session.isApplying)
        session.requestApply()   // double apply is ignored while the first runs
        let applied = await waitFor { !session.isApplying }
        XCTAssertTrue(applied)
        XCTAssertEqual(try names(in: dir), ["a_new.txt", "b_new.txt"])
        XCTAssertEqual(session.fileURLs.map(\.lastPathComponent), ["a_new.txt", "b_new.txt"])
        XCTAssertTrue(session.canUndo)

        session.undoLast()
        let undone = await waitFor { !session.isApplying && !session.canUndo }
        XCTAssertTrue(undone)
        XCTAssertEqual(try names(in: dir), ["a.txt", "b.txt"])
        XCTAssertEqual(session.fileURLs.map(\.lastPathComponent), ["a.txt", "b.txt"])
    }

    /// A file that cannot go back is reported and kept for a retry; the others are undone.
    func testUndoContinuesPastAFailedFile() async throws {
        let dir = try makeTempDir()
        let files = try makeFiles(["a.txt", "b.txt"], in: dir)
        let session = RenameSession(defaults: makeSuite())
        session.add(urls: files)
        session.template = "{name}_x"
        session.onConfigChanged()
        session.requestApply()
        let applied = await waitFor { !session.isApplying && session.canUndo }
        XCTAssertTrue(applied)

        try Data("blocker".utf8).write(to: dir.appendingPathComponent("a.txt"))
        session.undoLast()
        let undone = await waitFor { !session.isApplying && session.failureReport != nil }
        XCTAssertTrue(undone)
        XCTAssertEqual(try names(in: dir), ["a.txt", "a_x.txt", "b.txt"])
        XCTAssertEqual(session.failureReport?.failures.count, 1)
        XCTAssertTrue(session.canUndo)

        try FileManager.default.removeItem(at: dir.appendingPathComponent("a.txt"))
        session.failureReport = nil
        session.undoLast()
        let retried = await waitFor { !session.isApplying && !session.canUndo }
        XCTAssertTrue(retried)
        XCTAssertEqual(try names(in: dir), ["a.txt", "b.txt"])
    }

    /// A runaway regex is cut off by the plan's time budget, off the main actor.
    func testCatastrophicRegexDoesNotBlockTheMainActor() async throws {
        let dir = try makeTempDir()
        let files = try makeFiles([String(repeating: "a", count: 40) + "!.txt"], in: dir)
        let session = RenameSession(defaults: makeSuite())
        session.add(urls: files)
        session.isRegex = true
        session.search = "(a+)+b"
        session.onConfigChanged()

        var maxGap: TimeInterval = 0
        var last = Date()
        let flagged = await waitFor({
            let now = Date()
            maxGap = max(maxGap, now.timeIntervalSince(last))
            last = now
            return session.rows.first?.message == "Wyrażenie regularne zbyt wolne"
        }, timeout: 15)
        XCTAssertTrue(flagged)
        XCTAssertLessThan(maxGap, 0.5)
        XCTAssertFalse(session.canApply)
    }

    /// Two windows share the preset store; neither may drop the other's presets.
    func testPresetsFromOtherWindowsAreKept() {
        let suite = makeSuite()
        let one = RenameSession(defaults: suite)
        let two = RenameSession(defaults: suite)
        one.saveCurrentAsPreset(name: "A")
        two.saveCurrentAsPreset(name: "B")
        XCTAssertEqual(PresetStore(defaults: suite).load().map(\.name), ["A", "B"])
        XCTAssertEqual(two.presets.map(\.name), ["A", "B"])

        let a = two.presets[0].id
        let b = two.presets[1].id
        two.deletePreset(id: a)
        one.renamePreset(id: b, to: "C")
        XCTAssertEqual(PresetStore(defaults: suite).load().map(\.name), ["C"])
        XCTAssertEqual(one.presets.map(\.name), ["C"])
    }

    func testAddURLsWithNothingUsable() {
        let session = RenameSession(defaults: makeSuite())
        session.add(urls: [])
        session.add(urls: [URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")])
        XCTAssertTrue(session.fileURLs.isEmpty)
        XCTAssertFalse(session.canApply)
    }
}
