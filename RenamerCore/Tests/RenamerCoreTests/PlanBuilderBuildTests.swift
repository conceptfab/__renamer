import XCTest
@testable import RenamerCore

private struct NoProbe: FileSystemProbe { func exists(_ url: URL) -> Bool { false } }

final class PlanBuilderBuildTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }
    private let builder = PlanBuilder(evaluator: TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!))

    func test_buildsRowsWithCounterByOrder() {
        let cfg = RenameConfig(template: "f_{counter:01}.{ext}",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)
        let rows = builder.build(items: [item("/h/a.jpg"), item("/h/b.jpg")], config: cfg, probe: NoProbe())
        XCTAssertEqual(rows.map(\.proposedName), ["f_01.jpg", "f_02.jpg"])
        XCTAssertEqual(rows.map(\.status), [.ok, .ok])
    }

    func test_badTemplateMarksAllRowsError() {
        let cfg = RenameConfig(template: "{bogus}",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)
        let rows = builder.build(items: [item("/h/a.jpg")], config: cfg, probe: NoProbe())
        XCTAssertEqual(rows[0].status, .error)
        XCTAssertNotNil(rows[0].message)
    }
}
