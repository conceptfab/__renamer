import XCTest
@testable import RenamerCore

final class PipelineTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }
    private let builder = PlanBuilder(evaluator: TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!))

    func test_templateThenCounter() throws {
        let cfg = RenameConfig(template: "photo_{counter:001}.{ext}",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)
        XCTAssertEqual(try builder.proposedName(for: item("/h/IMG.JPG"), index: 0, config: cfg), "photo_001.JPG")
    }

    func test_emptyTemplateUsesOriginalThenFindReplace() throws {
        let cfg = RenameConfig(template: "",
                               find: FindReplace(search: "IMG", replacement: "foto", isRegex: false, caseSensitive: true),
                               nameCase: .none, extCase: .none, stripDiacritics: false)
        XCTAssertEqual(try builder.proposedName(for: item("/h/IMG_1.jpg"), index: 0, config: cfg), "foto_1.jpg")
    }

    func test_separateCaseForNameAndExt() throws {
        let cfg = RenameConfig(template: "",
                               find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                               nameCase: .upper, extCase: .lower, stripDiacritics: false)
        XCTAssertEqual(try builder.proposedName(for: item("/h/Report.TXT"), index: 0, config: cfg), "REPORT.txt")
    }
}
