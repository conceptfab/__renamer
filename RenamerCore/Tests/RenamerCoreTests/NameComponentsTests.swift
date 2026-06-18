import XCTest
@testable import RenamerCore

final class NameComponentsTests: XCTestCase {
    func test_splitsBaseAndExtension() {
        let c = NameComponents(fullName: "photo.JPG")
        XCTAssertEqual(c.base, "photo")
        XCTAssertEqual(c.ext, "JPG")
        XCTAssertTrue(c.hadDot)
        XCTAssertEqual(c.fullName, "photo.JPG")
    }

    func test_noExtension() {
        let c = NameComponents(fullName: "README")
        XCTAssertEqual(c.base, "README")
        XCTAssertEqual(c.ext, "")
        XCTAssertFalse(c.hadDot)
    }

    func test_leadingDotIsNotExtension() {
        let c = NameComponents(fullName: ".gitignore")
        XCTAssertEqual(c.base, ".gitignore")
        XCTAssertEqual(c.ext, "")
        XCTAssertFalse(c.hadDot)
    }

    func test_multipleDotsUseLast() {
        let c = NameComponents(fullName: "archive.tar.gz")
        XCTAssertEqual(c.base, "archive.tar")
        XCTAssertEqual(c.ext, "gz")
    }

    func test_recomposeFromParts() {
        XCTAssertEqual(NameComponents(base: "a", ext: "txt", hadDot: true).fullName, "a.txt")
        XCTAssertEqual(NameComponents(base: "a", ext: "", hadDot: false).fullName, "a")
    }
}
