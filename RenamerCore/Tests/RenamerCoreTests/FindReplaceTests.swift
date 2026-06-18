import XCTest
@testable import RenamerCore

final class FindReplaceTests: XCTestCase {
    func test_emptySearchIsNoop() throws {
        let fr = FindReplace(search: "", replacement: "x", isRegex: false, caseSensitive: true)
        XCTAssertEqual(try fr.apply(to: "hello"), "hello")
    }

    func test_plainReplaceAll() throws {
        let fr = FindReplace(search: "a", replacement: "X", isRegex: false, caseSensitive: true)
        XCTAssertEqual(try fr.apply(to: "banana"), "bXnXnX")
    }

    func test_plainCaseInsensitive() throws {
        let fr = FindReplace(search: "img", replacement: "photo", isRegex: false, caseSensitive: false)
        XCTAssertEqual(try fr.apply(to: "IMG_01"), "photo_01")
    }

    func test_regexWithGroup() throws {
        let fr = FindReplace(search: "IMG_(\\d+)", replacement: "photo_$1", isRegex: true, caseSensitive: true)
        XCTAssertEqual(try fr.apply(to: "IMG_2381"), "photo_2381")
    }

    func test_badRegexThrows() {
        let fr = FindReplace(search: "(", replacement: "", isRegex: true, caseSensitive: true)
        XCTAssertThrowsError(try fr.apply(to: "x"))
    }
}
