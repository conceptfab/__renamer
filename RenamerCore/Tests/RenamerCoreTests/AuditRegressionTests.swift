import XCTest
@testable import RenamerCore

/// Regression tests for the safety audit (names, overflow, case mapping, regex runaway).
private struct Probe: FileSystemProbe {
    var existing: Set<String> = []
    var directories: Set<String> = []
    func exists(_ url: URL) -> Bool { existing.contains(url.path) || directories.contains(url.path) }
    func isDirectory(_ url: URL) -> Bool { directories.contains(url.path) }
}

final class AuditRegressionTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }
    private func row(_ original: String, _ proposed: String) -> RenameRow {
        RenameRow(item: item("/h/d/" + original), proposedName: proposed, status: .ok, message: nil)
    }
    private func config(template: String = "", search: String = "", replacement: String = "",
                        isRegex: Bool = false) -> RenameConfig {
        RenameConfig(template: template,
                     find: FindReplace(search: search, replacement: replacement, isRegex: isRegex, caseSensitive: true),
                     nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: false)
    }

    // MARK: Names

    func test_dotAndDotDotAreErrors() {
        // "/h/d/.." exists (it is the parent folder) — must still be an error, not a warning.
        let out = CollisionDetector.annotate([row("a.txt", "."), row("b.txt", "..")],
                                             probe: Probe(directories: ["/h/d/..", "/h/d/.", "/h", "/h/d"]))
        XCTAssertEqual(out.map(\.status), [.error, .error])
        XCTAssertEqual(out.map(\.message), ["Niedozwolona nazwa", "Niedozwolona nazwa"])
    }

    func test_nameLongerThan255BytesIsError() {
        let ok = String(repeating: "ą", count: 127) + "a"      // 255 bytes
        let tooLong = String(repeating: "ą", count: 128)       // 256 bytes
        let out = CollisionDetector.annotate([row("a.txt", ok), row("b.txt", tooLong)], probe: Probe())
        XCTAssertEqual(out.map(\.status), [.ok, .error])
    }

    func test_dotfilesAreAllowed() {
        let out = CollisionDetector.annotate([row("a.txt", ".env"), row("b.txt", "...x")], probe: Probe())
        XCTAssertEqual(out.map(\.status), [.ok, .ok])
    }

    func test_existingFolderAtTargetIsError() {
        let out = CollisionDetector.annotate([row("a.txt", "Folder")], probe: Probe(directories: ["/h/d/Folder"]))
        XCTAssertEqual(out[0].status, .error)
    }

    // MARK: Case mapping

    func test_titleCaseWithMultiScalarUppercase() {
        XCTAssertEqual(CaseTransformer.apply("ßa ﬁx", mode: .title, stripDiacritics: false), "SSa FIx")
        XCTAssertEqual(CaseTransformer.apply("ŉb", mode: .title, stripDiacritics: false), "ʼNb")
    }

    // MARK: Counter

    func test_counterOverflowThrows() throws {
        let spec = try CounterSpec.parse("start=\(Int.max)")
        XCTAssertEqual(try spec.format(forIndex: 0), String(Int.max))
        XCTAssertThrowsError(try spec.format(forIndex: 1))
        XCTAssertThrowsError(try CounterSpec.parse("step=\(Int.max)").format(forIndex: 2))
    }

    func test_counterIntMinFormats() throws {
        let spec = try CounterSpec.parse("start=\(Int.min)")
        XCTAssertEqual(try spec.format(forIndex: 0), String(Int.min))
    }

    func test_counterHugeDigitsRejected() {
        XCTAssertThrowsError(try CounterSpec.parse("digits=1000000000000"))
        XCTAssertThrowsError(try CounterSpec.parse(String(repeating: "0", count: 300)))
        XCTAssertNoThrow(try CounterSpec.parse("digits=10"))
    }

    func test_counterOverflowBecomesRowError() {
        let rows = PlanBuilder().build(items: [item("/h/a.txt"), item("/h/b.txt")],
                                       config: config(template: "{counter:start=\(Int.max)}"),
                                       probe: Probe())
        XCTAssertEqual(rows.map(\.status), [.ok, .error])
    }

    // MARK: Plan

    func test_replacementTokensExpandPerFile() {
        let rows = PlanBuilder().build(items: [item("/h/a.txt"), item("/h/b.txt")],
                                       config: config(search: "^.", replacement: "{counter}_", isRegex: true),
                                       probe: Probe())
        XCTAssertEqual(rows.map(\.proposedName), ["1_.txt", "2_.txt"])
    }

    func test_regexReplacementTokenValuesAreLiteral() {
        // "$1" inside the file name must not expand; the user's own "$1" still does.
        let rows = PlanBuilder().build(items: [item("/h/Faktury $1 x.pdf")],
                                       config: config(search: "^(F)", replacement: "{name}-$1", isRegex: true),
                                       probe: Probe())
        XCTAssertEqual(rows.map(\.proposedName), ["Faktury $1 x-Faktury $1 x.pdf"])
    }

    func test_invalidRegexMarksAllRows() {
        let rows = PlanBuilder().build(items: [item("/h/a.txt"), item("/h/b.txt")],
                                       config: config(search: "(", isRegex: true), probe: Probe())
        XCTAssertEqual(rows.map(\.status), [.error, .error])
    }

    func test_catastrophicRegexIsStoppedByTimeBudget() {
        let name = String(repeating: "a", count: 40) + "!.txt"
        let start = Date()
        let rows = PlanBuilder().build(items: [item("/h/" + name), item("/h/x.txt")],
                                       config: config(search: "(a+)+b", isRegex: true),
                                       probe: Probe(), timeBudget: 0.2)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(rows.map(\.status), [.error, .error])
        XCTAssertEqual(rows.first?.message, "Wyrażenie regularne zbyt wolne")
    }

    func test_findReplaceRegexStillSupportsTemplates() throws {
        let fr = FindReplace(search: "(\\w)(\\w)", replacement: "$2$1", isRegex: true, caseSensitive: true)
        XCTAssertEqual(try fr.compiled().apply(to: "abcd e", replacement: fr.replacement), "badc e")
    }
}
