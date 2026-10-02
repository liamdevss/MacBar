import AppKit
import SwiftUI

enum ProfileLink {
    static let username = "liammdevs"
    static let handle = "@" + username
    static let url = URL(string: "https://x.com/\(username)")!
    static let photo: NSImage = {
        let url = Bundle.main.url(forResource: "ProfilePhoto", withExtension: "jpg")
            ?? Bundle.module.url(forResource: "ProfilePhoto", withExtension: "jpg", subdirectory: "Assets")
        return url.flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: "Profile photo")!
    }()
}

private final class ProfileButton: GlassButton {
    override init() {
        super.init()
        toolTip = "Show \(ProfileLink.handle) on X"
        setAccessibilityLabel(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let photoRect = NSRect(x: 3, y: bounds.midY - 12, width: 24, height: 24)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: photoRect).addClip()
        ProfileLink.photo.draw(in: photoRect, from: .zero, operation: .sourceOver, fraction: 1,
                              respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard bounds.width > 100 else { return }
        (ProfileLink.handle as NSString).draw(in: NSRect(x: 34, y: bounds.midY - 8, width: bounds.width - 38, height: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ])
    }
}

final class LauncherBarView: NSView {
    enum Panel { case none, spotify, profile, media }

    private let backdrop = BackgroundView()
    private let profile = ProfileButton()
    let appsScrollView = NSScrollView()
    private let document = NSView()
    private let spotifyButton = GlassButton()
    private let gameButton = GlassButton()
    private var game: FlappyGameView?
    let spotifyPanel = SpotifyPanelView()
    private let profilePanel = XProfilePanel()
    private let mediaPanel = MediaPanelView()
    private var dismissedSite: MediaSite?
    private let systemControls = SystemControlsView()
    private let status = StatusView()
    private let suggestionsView = SuggestionsView()
    private(set) var panel: Panel = .none
    private var isTyping = false
    private var typingProgress: CGFloat = 0
    private var animationTimer: Timer?
    private var intro: IntroOverlay?
    private var buttons: [AppButton] = []
    private var displayedApps: [AppEntry]?
    var profileFrame: NSRect { profile.frame }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(backdrop)
        addSubview(profile)
        profile.onPress = { [weak self] in self?.toggle(.profile) }
        appsScrollView.drawsBackground = false
        appsScrollView.contentView.drawsBackground = false
        appsScrollView.hasHorizontalScroller = false
        appsScrollView.hasVerticalScroller = false
        appsScrollView.horizontalScrollElasticity = .allowed
        appsScrollView.verticalScrollElasticity = .none
        appsScrollView.documentView = document
        addSubview(appsScrollView)
        mediaPanel.onClose = { [weak self] in
            self?.dismissedSite = self?.mediaPanel.site
            self?.setPanel(.none)
        }
        for panelView in [spotifyPanel, profilePanel, mediaPanel] as [NSView] {
            panelView.isHidden = true
            addSubview(panelView)
        }
        spotifyButton.image = Spotify.icon
        spotifyButton.toolTip = "Spotify controls"
        spotifyButton.setAccessibilityLabel("Show Spotify controls")
        spotifyButton.onPress = { [weak self] in self?.toggle(.spotify) }
        addSubview(spotifyButton)
        gameButton.image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Play Flappy Bar")
        gameButton.toolTip = "Flappy Bar"
        gameButton.onPress = { [weak self] in self?.openGame() }
        addSubview(gameButton)
        addSubview(status)
        addSubview(systemControls)
        suggestionsView.isHidden = true
        addSubview(suggestionsView)
        NotificationCenter.default.addObserver(self, selector: #selector(suggestionsChanged),
                                               name: .typingSuggestionsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appStateChanged),
                                               name: .appStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mediaSiteChanged),
                                               name: .mediaSiteChanged, object: nil)
    }

    @objc private func mediaSiteChanged() {
        let monitor = MediaSiteMonitor.shared
        guard let site = monitor.site, let browser = monitor.browser else {
            dismissedSite = nil
            if panel == .media { setPanel(.none) }
            return
        }
        guard site != dismissedSite, panel == .none || panel == .media else { return }
        if panel == .media, mediaPanel.site == site { return }
        mediaPanel.show(site: site, browser: browser, splash: true)
        if panel == .media { mediaPanel.setActive(true) } else { setPanel(.media) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    func openGame() {
        guard game == nil else { return }
        let view = FlappyGameView(frame: bounds, background: backdrop.image, mode: backdrop.mode)
        view.onExit = { [weak self] in self?.closeGame() }
        addSubview(view)
        game = view
        let push = CATransition()
        push.type = .push
        push.subtype = .fromRight
        push.duration = 0.3
        push.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(push, forKey: "game")
        view.start()
        FlappyKeyboard.shared.begin(onFlap: { [weak view] in view?.flap() },
                                    onExit: { [weak self] in self?.closeGame() })
    }

    func closeGame() {
        guard let game else { return }
        FlappyKeyboard.shared.end()
        game.stop()
        game.removeFromSuperview()
        self.game = nil
        let push = CATransition()
        push.type = .push
        push.subtype = .fromLeft
        push.duration = 0.3
        push.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(push, forKey: "game")
    }

    func playIntro() {
        let overlay = IntroOverlay(frame: bounds)
        addSubview(overlay)
        intro = overlay
        let gravity: CALayerContentsGravity = switch backdrop.mode {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        case .stretch: .resize
        }
        overlay.play(background: backdrop.image, gravity: gravity) { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            guard let self else { return }
            self.intro = nil
            let visibleButtons = self.buttons.filter { $0.frame.minX < self.appsScrollView.documentVisibleRect.maxX }
            let views: [NSView] = [self.profile] + visibleButtons + [self.spotifyButton, self.gameButton, self.status, self.systemControls]
            for (index, view) in views.enumerated() { Glass.appear(view, delay: Double(index) * 0.035) }
        }
    }

    private func toggle(_ target: Panel) { setPanel(panel == target ? .none : target) }

    func setPanel(_ newPanel: Panel) {
        guard newPanel != panel else { return }
        panel = newPanel
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.18
        layer?.add(fade, forKey: "panel")
        spotifyPanel.isHidden = newPanel != .spotify
        profilePanel.isHidden = newPanel != .profile
        mediaPanel.isHidden = newPanel != .media
        mediaPanel.setActive(newPanel == .media)
        appsScrollView.isHidden = newPanel != .none
        status.isHidden = newPanel != .none
        spotifyButton.isActive = newPanel == .spotify
        profile.isActive = newPanel == .profile
        spotifyPanel.setActive(newPanel == .spotify)
        if newPanel == .profile { profilePanel.refresh() }
        needsLayout = true
    }

    @objc private func suggestionsChanged() {
        let suggestions = TypingSuggestions.shared.suggestions
        suggestionsView.update(suggestions, appearing: !isTyping)
        let typing = !suggestions.isEmpty
        guard typing != isTyping else { return }
        isTyping = typing
        animationTimer?.invalidate()
        let from = typingProgress
        let to: CGFloat = typing ? 1 : 0
        let started = Date()
        let duration = 0.22
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let t = min(1, Date().timeIntervalSince(started) / duration)
            let eased = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
            self.typingProgress = from + (to - from) * eased
            self.needsLayout = true
            self.profile.needsDisplay = true
            if t >= 1 { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    @objc private func appStateChanged() {
        let state = AppStateMonitor.shared
        for (button, app) in zip(buttons, displayedApps ?? []) {
            button.badge = state.badges[app.bundleIdentifier]
        }
    }

    func update(store: LauncherStore) {
        backdrop.image = store.backgroundImage
        backdrop.mode = store.background.mode
        guard displayedApps != store.apps else { return }
        displayedApps = store.apps
        buttons.forEach { $0.removeFromSuperview() }
        buttons = store.apps.map { app in
            let button = AppButton()
            button.image = store.icon(app)
            button.toolTip = app.name
            button.setAccessibilityLabel("Open \(app.name)")
            button.onPress = { [weak store] in store?.launch(app) }
            document.addSubview(button)
            return button
        }
        appStateChanged()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let gap = Glass.gap
        backdrop.frame = bounds
        intro?.frame = bounds
        game?.frame = bounds
        let p = panel == .none ? typingProgress : 0
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        profile.frame = NSRect(x: 4, y: 0, width: mix(136, 30), height: bounds.height)
        let start = profile.frame.maxX + 8
        systemControls.frame = NSRect(x: bounds.width - SystemControlsView.preferredWidth, y: 0,
                                      width: SystemControlsView.preferredWidth, height: bounds.height)
        let statusWidth = status.isHidden ? 0 : StatusView.preferredWidth + gap
        status.frame = NSRect(x: systemControls.frame.minX - statusWidth, y: 0,
                              width: StatusView.preferredWidth, height: bounds.height)
        gameButton.frame = NSRect(x: (status.isHidden ? systemControls.frame.minX : status.frame.minX) - gap - 40,
                                  y: 0, width: 40, height: bounds.height)
        spotifyButton.frame = NSRect(x: gameButton.frame.minX - gap - 40, y: 0, width: 40, height: bounds.height)
        let middle = NSRect(x: start, y: 0, width: max(0, spotifyButton.frame.minX - gap - start), height: bounds.height)
        spotifyPanel.frame = middle
        profilePanel.frame = middle
        mediaPanel.frame = middle
        let pitch = mix(46 + gap, 30)
        let icon = NSSize(width: mix(46, 26), height: mix(30, 22))
        let contentWidth = max(0, CGFloat(buttons.count) * pitch - (pitch - icon.width))
        let compactWidth = min(contentWidth, middle.width * 0.35)
        appsScrollView.frame = NSRect(x: start, y: 0, width: mix(middle.width, compactWidth), height: bounds.height)
        let suggestionsX = appsScrollView.frame.maxX + gap
        suggestionsView.frame = NSRect(x: suggestionsX, y: 0, width: max(0, middle.maxX - suggestionsX), height: bounds.height)
        suggestionsView.alphaValue = p
        suggestionsView.isHidden = p == 0
        document.frame = NSRect(x: 0, y: 0, width: max(contentWidth, appsScrollView.contentSize.width), height: bounds.height)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * pitch, y: (bounds.height - icon.height) / 2,
                                  width: icon.width, height: icon.height)
        }
        let oldX = appsScrollView.contentView.bounds.minX
        let maxX = max(0, document.frame.width - appsScrollView.contentSize.width)
        appsScrollView.contentView.scroll(to: NSPoint(x: min(maxX, max(0, oldX)), y: 0))
        appsScrollView.reflectScrolledClipView(appsScrollView.contentView)
    }
}

struct LauncherBarPreview: NSViewRepresentable {
    @ObservedObject var store: LauncherStore
    func makeNSView(context: Context) -> LauncherBarView { LauncherBarView(frame: .zero) }
    func updateNSView(_ view: LauncherBarView, context: Context) { view.update(store: store) }
}

final class SuggestionsView: NSView {
    private var buttons: [GlassButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ suggestions: [TypingSuggestions.Suggestion], appearing: Bool) {
        guard !suggestions.isEmpty else { return }
        buttons.forEach { $0.removeFromSuperview() }
        buttons = suggestions.map { suggestion in
            let button = GlassButton()
            button.setTitle(suggestion.display, size: 14)
            button.lineBreakMode = .byTruncatingTail
            button.setAccessibilityLabel("Use \(suggestion.display)")
            button.onPress = { TypingSuggestions.shared.apply(suggestion) }
            addSubview(button)
            return button
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if appearing {
            for (index, button) in buttons.enumerated() { Glass.appear(button, delay: 0.08 + Double(index) * 0.06) }
        }
    }

    override func layout() {
        super.layout()
        guard !buttons.isEmpty else { return }
        let width = (bounds.width - Glass.gap * CGFloat(buttons.count - 1)) / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * (width + Glass.gap), y: 0, width: max(0, width), height: bounds.height)
        }
    }
}
