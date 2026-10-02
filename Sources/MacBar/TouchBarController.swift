import AppKit

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    private let store: LauncherStore
    private let presentation: TouchBarPresenting
    private var bar: NSTouchBar?
    private var trayItem: NSCustomTouchBarItem?
    private var requestedVisible = false
    private var suspended = false
    private var stopped = false
    private var recoveryTask: Task<Void, Never>?
    private let appsIdentifier = NSTouchBarItem.Identifier("dev.macbar.apps")
    private let trayIdentifier = NSTouchBarItem.Identifier("dev.macbar.controlstrip")

    init(store: LauncherStore, presentation: TouchBarPresenting? = nil) {
        self.store = store
        self.presentation = presentation ?? SystemTouchBarPresentation()
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(self, selector: #selector(suspend), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(resume), name: name, object: nil)
        }
    }

    @objc func show() {
        guard !stopped else { return }
        requestedVisible = true
        if trayItem == nil {
            let item = NSCustomTouchBarItem(identifier: trayIdentifier)
            let button = NSButton(image: NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Show MacBar")!, target: self, action: #selector(show))
            button.setAccessibilityLabel("Show MacBar")
            item.view = button
            if presentation.register(item) { trayItem = item }
        }
        if bar == nil { buildBar() }
        restoreIfNeeded()
    }

    private func buildBar() {
        let newBar = NSTouchBar()
        newBar.delegate = self
        newBar.defaultItemIdentifiers = [appsIdentifier]
        bar = newBar
    }

    func restoreIfNeeded() {
        guard requestedVisible, !suspended, !stopped, let bar else { return }
        if !presentation.present(bar, trayIdentifier: trayItem?.identifier.rawValue) {
            requestedVisible = false
            store.errorMessage = "This macOS version doesn’t expose the global Touch Bar API. You can still use the on-screen preview."
        }
    }

    @objc func hide() {
        requestedVisible = false
        recoveryTask?.cancel()
        if let bar { presentation.dismiss(bar) }
    }

    @objc func workspaceChanged() {
        guard requestedVisible, !suspended, !stopped else { return }
        recoveryTask?.cancel()
        recoveryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 200_000_000) }
            catch { return }
            self?.restoreIfNeeded()
        }
    }

    @objc func suspend() {
        suspended = true
        recoveryTask?.cancel()
    }

    @objc func resume() {
        suspended = false
        workspaceChanged()
    }

    func shutdown() {
        hide()
        stopped = true
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let trayItem { presentation.remove(trayItem) }
        trayItem = nil
        bar = nil
    }

    func refresh() {
        if let bar { presentation.dismiss(bar) }
        buildBar()
        restoreIfNeeded()
    }

    private static var introPlayed = false

    static var barWidth: CGFloat {
        let stored = UserDefaults.standard.double(forKey: "barWidth")
        return stored > 0 ? CGFloat(stored) : 1004
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        guard identifier == appsIdentifier else { return nil }
        let barWidth = Self.barWidth
        let launcher = LauncherBarView(frame: NSRect(x: 0, y: 0, width: barWidth, height: 30))
        launcher.update(store: store)
        NSLayoutConstraint.activate([
            launcher.heightAnchor.constraint(equalToConstant: 30),
            launcher.widthAnchor.constraint(equalToConstant: barWidth)
        ])
        item.view = launcher
        if !Self.introPlayed {
            Self.introPlayed = true
            launcher.playIntro()
        }
        return item
    }
}
