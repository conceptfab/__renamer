import XCTest
@testable import RenamerCore

final class TemplateEvaluatorTests: XCTestCase {
    private let evaluator = TemplateEvaluator(
        locale: Locale(identifier: "en_US_POSIX"),
        timeZone: TimeZone(identifier: "UTC")!
    )

    private func item(_ path: String, date: Date = Date(timeIntervalSince1970: 0)) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: date)
    }

    private func eval(_ template: String, _ item: FileItem, _ index: Int = 0) throws -> String {
        try evaluator.evaluate(TemplateParser.parse(template), item: item, index: index)
    }

    func test_nameAndExt() throws {
        let i = item("/h/Trip/IMG_01.jpg")
        XCTAssertEqual(try eval("{name}.{ext}", i), "IMG_01.jpg")
    }

    func test_parent() throws {
        XCTAssertEqual(try eval("{parent}_{name}", item("/h/Trip/a.txt")), "Trip_a")
    }

    func test_counter() throws {
        let i = item("/h/a.txt")
        XCTAssertEqual(try eval("img_{counter:001}", i, 4), "img_005")
    }

    func test_caseKeyword() throws {
        XCTAssertEqual(try eval("{name:upper}", item("/h/abc.txt")), "ABC")
    }

    func test_fragment() throws {
        XCTAssertEqual(try eval("{name:1-3}", item("/h/abcdef.txt")), "abc")
    }

    func test_dateUsesModificationDate() throws {
        // 2021-01-02T03:04:05Z
        let d = Date(timeIntervalSince1970: 1_609_556_645)
        XCTAssertEqual(try eval("{date}", item("/h/a.txt", date: d)), "2021-01-02")
        XCTAssertEqual(try eval("{time}", item("/h/a.txt", date: d)), "03-04-05")
        XCTAssertEqual(try eval("{date:yyyyMMdd}", item("/h/a.txt", date: d)), "20210102")
    }

    func test_badFragmentOrKeywordThrows() {
        XCTAssertThrowsError(try eval("{name:nonsense!}", item("/h/a.txt")))
    }
}
