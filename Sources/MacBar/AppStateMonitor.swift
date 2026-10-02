import AppKit
import ApplicationServices

extension Notification.Name {
    static let appStateChanged = Notification.Name("dev.macbar.appStateChanged")
}

final class AppStateMonitor {
    static let shared = AppStateMonitor()

    private(set) var badges: [String: String] = [:]
    private var timer: Timer?
    private var bundleIDs: [URL: String] = [:]

    func start() {
        guard timer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    @objc func refresh() {
        let newBadges = dockBadges()
        guard newBadges != badges else { return }
        badges = newBadges
        NotificationCenter.default.post(name: .appStateChanged, object: nil)
    }

    private func dockBadges() -> [String: String] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        var result: [String: String] = [:]
        for list in children(of: AXUIElementCreateApplication(dock.processIdentifier)) {
            for item in children(of: list) {
                guard let label = attribute(item, "AXStatusLabel") as? String, !label.isEmpty,
                      let url = attribute(item, kAXURLAttribute) as? URL else { continue }
                let id = bundleIDs[url] ?? Bundle(url: url)?.bundleIdentifier
                bundleIDs[url] = id
                if let id { result[id] = label }
            }
        }
        return result
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}
