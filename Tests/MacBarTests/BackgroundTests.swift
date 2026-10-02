import AppKit
import XCTest
@testable import MacBar

final class BackgroundTests: XCTestCase {
    func testExistingConfigWithoutBackgroundStillDecodes() throws {
        let oldJSON = Data(#"{"apps":[{"name":"Safari","bundleIdentifier":"com.apple.Safari"}]}"#.utf8)
        let config = try JSONDecoder().decode(Configuration.self, from: oldJSON).validated()
        XCTAssertNil(config.background)
        XCTAssertEqual(config.apps.count, 1)
    }

    @MainActor
    func testBackgroundSurvivesAppEditsAndReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("apps.json")
        let first = AppEntry(name: "Finder", bundleIdentifier: "com.apple.finder")
        let second = AppEntry(name: "Safari", bundleIdentifier: "com.apple.Safari")
        try Configuration(apps: [first, second]).save(to: url)
        let store = LauncherStore(configurationURL: url)
        XCTAssertNotNil(store.backgroundImage)
        let settings = BackgroundSettings(mode: .stretch, isEnabled: false)
        store.setBackground(settings)
        store.move(second, by: -1)
        store.reload()
        XCTAssertEqual(store.background, settings)
        XCTAssertNil(store.backgroundImage)
        XCTAssertEqual(store.apps.map(\.id), [second.id, first.id])
        XCTAssertEqual(try Configuration.read(from: url).background, settings)

        let before = try Data(contentsOf: url)
        store.setBackground(BackgroundSettings(imagePath: directory.appendingPathComponent("missing.png").path))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.background, settings)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
}
