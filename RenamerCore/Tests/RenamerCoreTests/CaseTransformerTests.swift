import XCTest
@testable import RenamerCore

final class CaseTransformerTests: XCTestCase {
    func test_none() {
        XCTAssertEqual(CaseTransformer.apply("MixedCase", mode: .none, stripDiacritics: false), "MixedCase")
    }
    func test_lowerUpper() {
        XCTAssertEqual(CaseTransformer.apply("AbC", mode: .lower, stripDiacritics: false), "abc")
        XCTAssertEqual(CaseTransformer.apply("AbC", mode: .upper, stripDiacritics: false), "ABC")
    }
    func test_title() {
        XCTAssertEqual(CaseTransformer.apply("hello world-again", mode: .title, stripDiacritics: false),
                       "Hello World-Again")
    }
    func test_stripDiacritics() {
        XCTAssertEqual(CaseTransformer.apply("café", mode: .none, stripDiacritics: true), "cafe")
        XCTAssertEqual(CaseTransformer.apply("ąź", mode: .none, stripDiacritics: true), "az")
    }
}
