import XCTest
@testable import RenamerCore

final class ReplaceTokensTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }
    private let builder = PlanBuilder(evaluator: TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!))

    func test_counterTokenInReplacementExpandsPerIndex() throws {
        let cfg = RenameConfig(
            template: "",
            find: FindReplace(search: "x", replacement: "{counter:01}", isRegex: false, caseSensitive: true),
            nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: true)
        XCTAssertEqual(try builder.proposedName(for: item("/h/x.txt"), index: 0, config: cfg), "01.txt")
        XCTAssertEqual(try builder.proposedName(for: item("/h/x.txt"), index: 4, config: cfg), "05.txt")
    }

    func test_regexGroupAndTokenCoexist() throws {
        let cfg = RenameConfig(
            template: "",
            find: FindReplace(search: "IMG_(\\d+)", replacement: "{counter:001}_$1",
                              isRegex: true, caseSensitive: true),
            nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: true)
        XCTAssertEqual(try builder.proposedName(for: item("/h/IMG_42.jpg"), index: 0, config: cfg),
                       "001_42.jpg")
    }

    func test_emptyReplacementUnaffected() throws {
        let cfg = RenameConfig(
            template: "",
            find: FindReplace(search: "_old", replacement: "", isRegex: false, caseSensitive: true),
            nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: true)
        XCTAssertEqual(try builder.proposedName(for: item("/h/a_old.txt"), index: 0, config: cfg), "a.txt")
    }
}
