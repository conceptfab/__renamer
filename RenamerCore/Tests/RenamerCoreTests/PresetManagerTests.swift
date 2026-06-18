import XCTest
@testable import RenamerCore

final class PresetManagerTests: XCTestCase {
    private func preset(_ id: String, _ name: String) -> Preset {
        Preset(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(id)")!,
               name: name,
               config: RenameConfig(template: "",
                                    find: FindReplace(search: "", replacement: "", isRegex: false, caseSensitive: true),
                                    nameCase: .none, extCase: .none, stripDiacritics: false, lockExtension: true))
    }

    func test_add() {
        let result = PresetManager.add(preset("01", "A"), to: [])
        XCTAssertEqual(result.map(\.name), ["A"])
    }

    func test_delete() {
        let a = preset("01", "A"); let b = preset("02", "B")
        let result = PresetManager.delete(id: a.id, from: [a, b])
        XCTAssertEqual(result.map(\.name), ["B"])
    }

    func test_deleteUnknownIdLeavesListUnchanged() {
        let a = preset("01", "A")
        let result = PresetManager.delete(id: preset("99", "X").id, from: [a])
        XCTAssertEqual(result.map(\.name), ["A"])
    }

    func test_rename() {
        let a = preset("01", "A")
        let result = PresetManager.rename(id: a.id, to: "Renamed", in: [a])
        XCTAssertEqual(result.map(\.name), ["Renamed"])
    }

    func test_renameUnknownIdLeavesListUnchanged() {
        let a = preset("01", "A")
        let result = PresetManager.rename(id: preset("99", "X").id, to: "Z", in: [a])
        XCTAssertEqual(result.map(\.name), ["A"])
    }

    func test_presetRoundTrips() throws {
        let a = preset("01", "A")
        let data = try JSONEncoder().encode([a])
        XCTAssertEqual(try JSONDecoder().decode([Preset].self, from: data), [a])
    }
}
