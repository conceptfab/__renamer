import XCTest
@testable import RenamerCore

final class FileItemTests: XCTestCase {
    private func item(_ path: String) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), modificationDate: Date(timeIntervalSince1970: 0))
    }

    func test_derivesNameParts() {
        let i = item("/Users/me/Holiday/IMG_01.jpg")
        XCTAssertEqual(i.fullName, "IMG_01.jpg")
        XCTAssertEqual(i.baseName, "IMG_01")
        XCTAssertEqual(i.ext, "jpg")
        XCTAssertEqual(i.parentName, "Holiday")
        XCTAssertEqual(i.directory, URL(fileURLWithPath: "/Users/me/Holiday"))
    }

    func test_noExtension() {
        let i = item("/tmp/README")
        XCTAssertEqual(i.baseName, "README")
        XCTAssertEqual(i.ext, "")
    }
}
