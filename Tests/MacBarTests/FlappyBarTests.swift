import AppKit
import XCTest
@testable import MacBar

final class FlappyBarTests: XCTestCase {
    @MainActor
    func testGameRunsAndRenders() throws {
        _ = NSApplication.shared
        let game = FlappyGameView(frame: NSRect(x: 0, y: 0, width: 1004, height: 30), background: nil, mode: .fill)
        game.start()
        game.flap()
        let end = Date().addingTimeInterval(1.6)
        while Date() < end {
            game.flap()
            RunLoop.main.run(until: Date().addingTimeInterval(0.28))
        }
        game.stop()
        if let path = ProcessInfo.processInfo.environment["MACBAR_PREVIEW_PATH"] {
            let bitmap = try XCTUnwrap(game.bitmapImageRepForCachingDisplay(in: game.bounds))
            game.cacheDisplay(in: game.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-flappy.png")))
        }
    }
}

final class ShowcaseTests: XCTestCase {
    @MainActor
    func testShowcaseRenders() throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Configuration(apps: [AppEntry(name: "Finder", bundleIdentifier: "com.apple.finder")]).save(to: url)
        let view = ShowcaseView(store: LauncherStore(configurationURL: url))
        view.keyEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!)
        view.layoutSubtreeIfNeeded()
        guard let path = ProcessInfo.processInfo.environment["MACBAR_PREVIEW_PATH"] else { return }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-showcase.png")))
    }
}
