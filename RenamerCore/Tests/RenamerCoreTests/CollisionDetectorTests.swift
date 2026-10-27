import XCTest
@testable import RenamerCore

private struct FakeProbe: FileSystemProbe {
    let existing: Set<String>
    func exists(_ url: URL) -> Bool { existing.contains(url.path) }
}

final class CollisionDetectorTests: XCTestCase {
    private func row(_ dir: String, _ original: String, _ proposed: String) -> RenameRow {
        let item = FileItem(url: URL(fileURLWithPath: dir).appendingPathComponent(original),
                            modificationDate: Date(timeIntervalSince1970: 0))
        return RenameRow(item: item, proposedName: proposed, status: .ok, message: nil)
    }

    func test_invalidCharacterIsError() {
        let rows = [row("/h", "a.txt", "a/b.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: []))
        XCTAssertEqual(out[0].status, .error)
    }

    func test_emptyNameIsError() {
        let rows = [row("/h", "a.txt", "")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: []))
        XCTAssertEqual(out[0].status, .error)
    }

    func test_duplicateTargetsAreErrors() {
        let rows = [row("/h", "a.txt", "same.txt"), row("/h", "b.txt", "SAME.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: []))
        XCTAssertEqual(out[0].status, .error)
        XCTAssertEqual(out[1].status, .error)
    }

    func test_existingFileOnDiskIsWarning() {
        let rows = [row("/h", "a.txt", "taken.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: ["/h/taken.txt"]))
        XCTAssertEqual(out[0].status, .warning)
    }

    func test_renamingOntoOwnSourceIsNotWarning() {
        // Source b.txt exists on disk and is also being renamed; a.txt -> b.txt is fine.
        let rows = [row("/h", "a.txt", "b.txt"), row("/h", "b.txt", "c.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: ["/h/a.txt", "/h/b.txt"]))
        XCTAssertEqual(out[0].status, .ok)
        XCTAssertEqual(out[1].status, .ok)
    }

    func test_caseFoldedDuplicatesAreErrors() {
        // APFS treats ß/ss and Σ/σ/ς as the same name.
        let rows = [row("/h", "x.txt", "strasse.txt"), row("/h", "y.txt", "straße.txt"),
                    row("/h", "a.txt", "ΣΑΣ.txt"), row("/h", "b.txt", "σας.txt")]
        let out = CollisionDetector.annotate(rows, probe: FakeProbe(existing: []))
        XCTAssertEqual(out.map(\.status), [.error, .error, .error, .error])
    }

    func test_nameLengthFollowsAPFS() {
        XCTAssertTrue(CollisionDetector.isValidName(String(repeating: "ż", count: 100) + ".txt"))
        XCTAssertTrue(CollisionDetector.isValidName(String(repeating: "漢", count: 200)))
        XCTAssertFalse(CollisionDetector.isValidName(String(repeating: "ǖ", count: 90)))
    }
}
