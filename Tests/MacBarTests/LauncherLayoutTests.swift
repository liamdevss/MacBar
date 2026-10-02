import AppKit
import XCTest
@testable import MacBar

final class LauncherLayoutTests: XCTestCase {
    @MainActor
    func testIconsStartAfterProfileAndScrollingKeepsProfilePinned() async throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let apps = (0..<16).map { AppEntry(name: "App \($0)", bundleIdentifier: "dev.example.app\($0)") }
        try Configuration(apps: apps).save(to: url)
        let store = LauncherStore(configurationURL: url)
        let view = LauncherBarView(frame: NSRect(x: 0, y: 0, width: 1004, height: 30))
        view.update(store: store)
        view.layoutSubtreeIfNeeded()
        let scroll = view.appsScrollView
        let document = try XCTUnwrap(scroll.documentView)
        let first = try XCTUnwrap(document.subviews.first)
        let profileBefore = view.profileFrame
        XCTAssertEqual(profileBefore.minX, 4)
        XCTAssertEqual(first.convert(first.bounds, to: view).minX, profileBefore.maxX + 8, accuracy: 1)
        XCTAssertGreaterThan(document.frame.width, scroll.contentSize.width)
        scroll.contentView.scroll(to: NSPoint(x: 120, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertEqual(view.profileFrame, profileBefore)
        XCTAssertEqual(first.convert(first.bounds, to: view).minX, profileBefore.maxX + 8 - 120, accuracy: 1)
        XCTAssertEqual(ProfileLink.url.absoluteString, "https://x.com/liammdevs")
        XCTAssertTrue(ProfileLink.photo.isValid)

        if let path = ProcessInfo.processInfo.environment["MACBAR_PREVIEW_PATH"] {
            scroll.contentView.scroll(to: .zero)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path))
            view.setPanel(.profile)
            view.layoutSubtreeIfNeeded()
            let panelBitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: panelBitmap)
            try XCTUnwrap(panelBitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-profile.png")))
        }
    }
}
