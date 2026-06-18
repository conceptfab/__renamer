import XCTest
@testable import RenamerCore

final class ConfigCodableTests: XCTestCase {
    func test_renameConfigRoundTrips() throws {
        let cfg = RenameConfig(
            template: "photo_{counter:001}",
            find: FindReplace(search: "IMG", replacement: "foto", isRegex: true, caseSensitive: false),
            nameCase: .upper, extCase: .lower, stripDiacritics: true, lockExtension: true)
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(RenameConfig.self, from: data)
        XCTAssertEqual(decoded, cfg)
    }

    func test_caseModeRoundTrips() throws {
        for mode in CaseMode.allCases {
            let data = try JSONEncoder().encode(mode)
            XCTAssertEqual(try JSONDecoder().decode(CaseMode.self, from: data), mode)
        }
    }
}
