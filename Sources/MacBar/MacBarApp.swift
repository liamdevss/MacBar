import AppKit
import SwiftUI
import Combine
import ServiceManagement

@main
enum MacBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: LauncherStore!
    private var touchBar: TouchBarController!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var errorSubscription: AnyCancellable?
    private var showcase: ShowcaseWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let configURL: URL?
        if let index = arguments.firstIndex(of: "--config"), arguments.indices.contains(index + 1) {
            configURL = URL(fileURLWithPath: arguments[index + 1])
        } else { configURL = nil }
        store = LauncherStore(configurationURL: configURL)
        touchBar = TouchBarController(store: store)
        store.onChange = { [weak self] in self?.touchBar.refresh() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "MacBar")
        statusItem.button?.toolTip = "MacBar"
        let menu = NSMenu()
        add("Show Touch Bar", action: #selector(showBar), to: menu)
        add("Hide Touch Bar", action: #selector(hideBar), to: menu)
        add("Typing Suggestions", action: #selector(toggleSuggestions(_:)), to: menu)
        menu.items.last?.state = TypingSuggestions.isEnabled ? .on : .off
        configureLaunchAtLogin()
        add("Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), to: menu)
        menu.items.last?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add("Configure MacBar…", action: #selector(showSettings), to: menu, key: ",")
        add("Showcase…", action: #selector(showShowcase), to: menu)
        add("Reload Configuration", action: #selector(reload), to: menu)
        add("Show Config File", action: #selector(revealConfig), to: menu)
        menu.addItem(.separator())
        add("Quit MacBar", action: #selector(quit), to: menu, key: "q")
        statusItem.menu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacBar"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(store: store, showBar: { [weak self] in self?.showBar() }, hideBar: { [weak self] in self?.hideBar() }))
        window.center()
        errorSubscription = store.$errorMessage.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] _ in self?.showSettings() }
        AppStateMonitor.shared.start()
        XStatsStore.shared.start()
        MediaSiteMonitor.shared.start()
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunched") || arguments.contains("--preview-only") {
            defaults.set(true, forKey: "hasLaunched")
            showSettings()
        }
        if !arguments.contains("--preview-only") {
            showBar()
            TypingSuggestions.shared.start(prompt: true)
        }
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    @objc private func showBar() { touchBar.show() }
    @objc private func hideBar() { touchBar.hide() }
    @objc private func toggleSuggestions(_ sender: NSMenuItem) {
        TypingSuggestions.isEnabled.toggle()
        sender.state = TypingSuggestions.isEnabled ? .on : .off
        if TypingSuggestions.isEnabled { TypingSuggestions.shared.start(prompt: true) }
        else { TypingSuggestions.shared.stop() }
    }
    @objc private func reload() { store.reload() }
    @objc private func revealConfig() { store.revealConfiguration() }
    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    @objc private func showShowcase() {
        if showcase == nil { showcase = ShowcaseWindowController(store: store) }
        showcase?.present()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { touchBar.workspaceChanged() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func configureLaunchAtLogin() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "launchAtLoginConfigured") else { return }
        defaults.set(true, forKey: "launchAtLoginConfigured")
        try? SMAppService.mainApp.register()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            store.errorMessage = "Couldn’t change Launch at Login: \(error.localizedDescription)"
        }
        sender.state = service.status == .enabled ? .on : .off
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { touchBar?.shutdown() }
}
