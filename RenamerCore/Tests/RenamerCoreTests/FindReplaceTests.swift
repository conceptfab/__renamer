import XCTest
@testable import RenamerCore

final class FindReplaceTests: XCTestCase {
    private func apply(_ fr: FindReplace, _ input: String) throws -> String {
        try fr.compiled().apply(to: input, replacement: fr.replacement)
    }

    func test_emptySearchIsNoop() throws {
        let fr = FindReplace(search: "", replacement: "x", isRegex: false, caseSensitive: true)
        XCTAssertEqual(try apply(fr, "hello"), "hello")
    }

    func test_plainReplaceAll() throws {
        let fr = FindReplace(search: "a", replacement: "X", isRegex: false, caseSensitive: true)
        XCTAssertEqual(try apply(fr, "banana"), "bXnXnX")
    }

    func test_plainCaseInsensitive() throws {
        let fr = FindReplace(search: "img", replacement: "photo", isRegex: false, caseSensitive: false)
        XCTAssertEqual(try apply(fr, "IMG_01"), "photo_01")
    }

    func test_regexWithGroup() throws {
        let fr = FindReplace(search: "IMG_(\\d+)", replacement: "photo_$1", isRegex: true, caseSensitive: true)
        XCTAssertEqual(try apply(fr, "IMG_2381"), "photo_2381")
    }

    func test_badRegexThrows() {
        let fr = FindReplace(search: "(", replacement: "", isRegex: true, caseSensitive: true)
        XCTAssertThrowsError(try apply(fr, "x"))
    }
}
