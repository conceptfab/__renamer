import XCTest
@testable import RenamerCore

final class FileItemLoaderTests: XCTestCase {
    func test_loadsNameAndModificationDate() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loader-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("doc.txt")
        try "x".write(to: url, atomically: true, encoding: .utf8)

        let item = try FileItemLoader.load(url)
        XCTAssertEqual(item.fullName, "doc.txt")
        XCTAssertEqual(item.url, url)
        XCTAssertLessThan(abs(item.modificationDate.timeIntervalSinceNow), 60)
    }

    func test_missingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).txt")
        XCTAssertThrowsError(try FileItemLoader.load(url))
    }
}
