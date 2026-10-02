import AppKit
import XCTest
@testable import MacBar

@MainActor
private final class RecordingPresentation: TouchBarPresenting {
    var presentations: [NSTouchBar] = []
    var trayIdentifiers: [String?] = []
    var registered = 0
    var removed = 0
    var supported = true
    var traySupported = true
    func present(_ bar: NSTouchBar, trayIdentifier: String?) -> Bool {
        presentations.append(bar)
        trayIdentifiers.append(trayIdentifier)
        return supported
    }
    func dismiss(_ bar: NSTouchBar) {}
    func register(_ item: NSTouchBarItem) -> Bool { registered += 1; return traySupported }
    func remove(_ item: NSTouchBarItem) { removed += 1 }
}

final class TouchBarLifecycleTests: XCTestCase {
    @MainActor
    private func makeStore() throws -> LauncherStore {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Configuration(apps: []).save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return LauncherStore(configurationURL: url)
    }

    @MainActor
    func testRestoreKeepsSameBarAndRegistersSingleReturnButton() async throws {
        let presentation = RecordingPresentation()
        let controller = TouchBarController(store: try makeStore(), presentation: presentation)
        defer { controller.shutdown() }
        controller.show()
        controller.restoreIfNeeded()
        controller.show()
        XCTAssertEqual(presentation.registered, 1)
        XCTAssertEqual(presentation.presentations.count, 3)
        XCTAssertTrue(presentation.presentations[0] === presentation.presentations[2])
        XCTAssertEqual(presentation.trayIdentifiers[0], "dev.macbar.controlstrip")
        XCTAssertEqual(presentation.presentations[0].defaultItemIdentifiers.map(\.rawValue), ["dev.macbar.apps"])
    }

    @MainActor
    func testExplicitHideSurvivesTransitionsWakeAndConfigurationChanges() async throws {
        let presentation = RecordingPresentation()
        let controller = TouchBarController(store: try makeStore(), presentation: presentation)
        defer { controller.shutdown() }
        controller.show()
        controller.workspaceChanged()
        controller.hide()
        controller.suspend()
        controller.resume()
        controller.refresh()
        controller.restoreIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presentation.presentations.count, 1)
        controller.show()
        XCTAssertEqual(presentation.presentations.count, 2)
    }

    @MainActor
    func testSuspendAndShutdownPreventReappearance() async throws {
        let presentation = RecordingPresentation()
        let controller = TouchBarController(store: try makeStore(), presentation: presentation)
        controller.show()
        controller.suspend()
        controller.restoreIfNeeded()
        XCTAssertEqual(presentation.presentations.count, 1)
        controller.resume()
        controller.restoreIfNeeded()
        XCTAssertEqual(presentation.presentations.count, 2)
        controller.shutdown()
        controller.restoreIfNeeded()
        controller.show()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(presentation.presentations.count, 2)
        XCTAssertEqual(presentation.removed, 1)
    }

    @MainActor
    func testUnsupportedAPIDoesNotRetryOnEveryTransition() async throws {
        let presentation = RecordingPresentation()
        presentation.supported = false
        presentation.traySupported = false
        let store = try makeStore()
        let controller = TouchBarController(store: store, presentation: presentation)
        defer { controller.shutdown() }
        controller.show()
        controller.restoreIfNeeded()
        XCTAssertEqual(presentation.presentations.count, 1)
        XCTAssertNil(presentation.trayIdentifiers[0])
        XCTAssertNotNil(store.errorMessage)
    }
}
