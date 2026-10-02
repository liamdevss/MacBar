import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class LauncherStore: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var background = BackgroundSettings()
    @Published private(set) var backgroundImage: NSImage?
    @Published var errorMessage: String?
    @Published private(set) var runningIDs: Set<String> = []
    var onChange: (() -> Void)?
    let configurationURL: URL
    private var observers: [NSObjectProtocol] = []
    private var canSave = true

    init(configurationURL: URL? = nil) {
        self.configurationURL = configurationURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacBar/apps.json")
        reload()
        refreshRunningApps()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunningApps() }
            })
        }
    }

    func reload() {
        do {
            if FileManager.default.fileExists(atPath: configurationURL.path) {
                let config = try Configuration.read(from: configurationURL)
                let settings = config.background ?? BackgroundSettings()
                let image = try loadBackground(settings)
                apps = config.apps
                background = settings
                backgroundImage = image
            } else {
                background = BackgroundSettings()
                backgroundImage = try loadBackground(background)
                apps = dockApps()
                if apps.isEmpty {
                    apps = [AppEntry(name: "Finder", bundleIdentifier: "com.apple.finder"),
                            AppEntry(name: "Safari", bundleIdentifier: "com.apple.Safari")]
                }
            }
            canSave = true
            onChange?()
        } catch {
            canSave = false
            errorMessage = "Couldn’t read apps.json. Fix it and choose Reload Configuration.\n\n\(error.localizedDescription)"
        }
    }

    func appURL(_ entry: AppEntry) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleIdentifier) { return url }
        if let path = entry.path,
           Bundle(path: path)?.bundleIdentifier == entry.bundleIdentifier {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func icon(_ entry: AppEntry) -> NSImage {
        if let url = appURL(entry) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: entry.name)!
    }

    func launch(_ entry: AppEntry) {
        guard let url = appURL(entry) else {
            errorMessage = "\(entry.name) could not be found. Add its current application from the settings window."
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.errorMessage = "Couldn’t open \(entry.name): \(error.localizedDescription)" }
            }
        }
    }

    func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps for your Touch Bar"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        var updated = apps
        for url in panel.urls {
            guard let entry = entry(at: url) else { continue }
            if let index = updated.firstIndex(where: { $0.id == entry.id }) { updated[index] = entry }
            else { updated.append(entry) }
        }
        update(updated)
    }

    func remove(_ entry: AppEntry) { update(apps.filter { $0.id != entry.id }) }

    func chooseBackground() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Touch Bar background"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var settings = background
        settings.imagePath = url.path
        settings.isEnabled = true
        setBackground(settings)
    }

    func setBackground(_ settings: BackgroundSettings) {
        do {
            let image = try loadBackground(settings)
            guard persist(apps, background: settings) else { return }
            background = settings
            backgroundImage = image
            onChange?()
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadBackground(_ settings: BackgroundSettings) throws -> NSImage? {
        guard settings.isEnabled else { return nil }
        let url: URL?
        if let path = settings.imagePath { url = URL(fileURLWithPath: path) }
        else {
            url = Bundle.main.url(forResource: "DefaultBackground", withExtension: "jpg")
                ?? Bundle.module.url(forResource: "DefaultBackground", withExtension: "jpg", subdirectory: "Assets")
        }
        guard let url, let image = NSImage(contentsOf: url), image.isValid else {
            throw NSError(domain: "MacBar", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "The background image could not be read. Choose an existing PNG, JPEG, TIFF, or HEIC image, or use the default background."])
        }
        return image
    }

    func move(_ entry: AppEntry, by offset: Int) {
        guard let index = apps.firstIndex(of: entry), apps.indices.contains(index + offset) else { return }
        var updated = apps
        updated.swapAt(index, index + offset)
        update(updated)
    }

    func importDock() {
        let additions = dockApps().filter { candidate in !apps.contains(where: { $0.id == candidate.id }) }
        update(apps + additions)
    }

    func revealConfiguration() {
        if !FileManager.default.fileExists(atPath: configurationURL.path) {
            guard persist(apps) else { return }
        }
        NSWorkspace.shared.activateFileViewerSelecting([configurationURL])
    }

    private func update(_ updated: [AppEntry]) {
        guard persist(updated) else { return }
        apps = updated
        onChange?()
    }

    private func persist(_ updated: [AppEntry], background settings: BackgroundSettings? = nil) -> Bool {
        guard canSave else {
            errorMessage = "Your configuration has an error. Fix apps.json and reload before making changes; the file has been preserved."
            return false
        }
        do {
            try Configuration(apps: updated, background: settings ?? background).save(to: configurationURL)
            return true
        } catch {
            errorMessage = "Couldn’t save your apps: \(error.localizedDescription)"
            return false
        }
    }

    private func refreshRunningApps() {
        runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private func entry(at url: URL) -> AppEntry? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppEntry(name: name, bundleIdentifier: id, path: url.path)
    }

    private func dockApps() -> [AppEntry] {
        let tiles = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        var seen = Set<String>()
        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let value = file["_CFURLString"] as? String,
                  let url = URL(string: value), url.isFileURL,
                  let app = entry(at: url), seen.insert(app.id).inserted else { return nil }
            return app
        }
    }
}
