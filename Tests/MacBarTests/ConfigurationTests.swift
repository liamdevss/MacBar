import XCTest
@testable import MacBar

final class ConfigurationTests: XCTestCase {
    func testConfigurationRoundTripPreservesOrderAndOptionalPath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/apps.json")
        let config = Configuration(apps: [
            AppEntry(name: "Safari", bundleIdentifier: "com.apple.Safari"),
            AppEntry(name: "An App", bundleIdentifier: "dev.example.app", path: "/Applications/An App.app")
        ])
        try config.save(to: url)
        XCTAssertEqual(try Configuration.read(from: url), config)
    }

    func testInvalidEditDoesNotReplaceExistingConfiguration() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let entry = AppEntry(name: "Safari", bundleIdentifier: "com.apple.Safari")
        let original = Configuration(apps: [entry])
        try original.save(to: url)
        XCTAssertThrowsError(try Configuration(apps: [entry, entry]).save(to: url))
        XCTAssertEqual(try Configuration.read(from: url), original)
    }

    func testRejectsMalformedAndInvalidEntries() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(Configuration.self, from: Data("{bad json".utf8)))
        XCTAssertThrowsError(try Configuration(apps: [AppEntry(name: " ", bundleIdentifier: "id")]).validated())
        XCTAssertThrowsError(try Configuration(apps: [AppEntry(name: "App", bundleIdentifier: "id", path: "relative.app")]).validated())
        XCTAssertNoThrow(try Configuration(apps: []).validated())
    }
}
