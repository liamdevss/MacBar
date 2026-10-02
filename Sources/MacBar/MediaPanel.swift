import AppKit

final class MediaPanelView: NSView {
    var onClose: (() -> Void)?
    private(set) var site: MediaSite?
    private var browser: NSRunningApplication?

    private let logoButton = GlassButton()
    private let logo = MediaLogoView()
    private let artwork = NSImageView()
    private var artworkURL: URL?
    private let titleLabel = MarqueeLabel()
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let scrubber = ScrubSurface()
    private let back = GlassButton()
    private let play = GlassButton()
    private let forward = GlassButton()
    private let skip = GlassButton()
    private let speed = GlassButton()
    private let volumeDown = GlassButton()
    private let volumeUp = GlassButton()
    private var controls: [GlassButton] { [back, play, forward, skip, speed, volumeDown, volumeUp] }

    private let splash = NSView()
    private let splashLogo = MediaLogoView()
    private let splashLabel = NSTextField(labelWithString: "")
    private var splashing = false

    private var state: MediaControl.State?
    private var javaScript = false
    private var scrubFraction: CGFloat?
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        logoButton.toolTip = "Hide video controls"
        logoButton.onPress = { [weak self] in self?.onClose?() }
        logo.wantsLayer = true
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 5
        artwork.layer?.masksToBounds = true
        artwork.layer?.contentsGravity = .resizeAspectFill
        artwork.isHidden = true
        logoButton.addSubview(artwork)
        logoButton.addSubview(logo)
        addSubview(logoButton)
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        addSubview(titleLabel)
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        progressFill.wantsLayer = true
        progressTrack.addSubview(progressFill)
        addSubview(progressTrack)
        scrubber.onScrub = { [weak self] x, done in self?.scrub(to: x, done: done) }
        scrubber.onCancel = { [weak self] in self?.scrubFraction = nil; self?.render() }
        addSubview(scrubber)
        configure(back, "gobackward.10", "Back 10 seconds", .back)
        configure(play, "playpause.fill", "Play or pause", .toggle)
        configure(forward, "goforward.10", "Forward 10 seconds", .forward)
        configure(skip, "forward.end.fill", "Skip / next", .next)
        configure(speed, nil, "Playback speed", .speed)
        configure(volumeDown, "speaker.wave.1.fill", "Volume down", .volumeDown)
        configure(volumeUp, "speaker.wave.3.fill", "Volume up", .volumeUp)

        splash.wantsLayer = true
        splash.isHidden = true
        splashLogo.wantsLayer = true
        splashLabel.wantsLayer = true
        splash.addSubview(splashLogo)
        splashLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        splashLabel.textColor = .white
        splash.addSubview(splashLabel)
        addSubview(splash)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ button: GlassButton, _ symbol: String?, _ label: String, _ action: MediaControl.Action) {
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) }
        button.toolTip = label
        button.onPress = { [weak self] in self?.perform(action) }
        addSubview(button)
    }

    func show(site: MediaSite, browser: NSRunningApplication, splash showSplash: Bool) {
        self.site = site
        self.browser = browser
        state = nil
        loadArtwork(nil)
        logo.site = site
        splashLogo.site = site
        let accent = site == .youtube ? NSColor(srgbRed: 1, green: 0, blue: 0.2, alpha: 1) : NSColor(srgbRed: 0.9, green: 0.04, blue: 0.08, alpha: 1)
        progressFill.layer?.backgroundColor = accent.cgColor
        splashLabel.attributedStringValue = {
            let text = NSMutableAttributedString(string: site.name, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold)])
            text.append(NSAttributedString(string: " launched", attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.75)
            ]))
            text.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: site.name.count))
            return text
        }()
        if showSplash { playSplash() }
        render()
        needsLayout = true
    }

    private func playSplash() {
        splashing = true
        splash.isHidden = false
        setContent(hidden: true)
        layoutSubtreeIfNeeded()
        Glass.bounce(splashLogo)
        Glass.appear(splashLogo, delay: 0)
        Glass.appear(splashLabel, delay: 0.12)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.splashing else { return }
            self.splashing = false
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.25
            self.layer?.add(fade, forKey: "splash")
            self.splash.isHidden = true
            self.setContent(hidden: false)
            let views: [NSView] = [self.logoButton] + self.controls
            for (index, view) in views.enumerated() { Glass.appear(view, delay: Double(index) * 0.035) }
        }
    }

    private func setContent(hidden: Bool) {
        for view in [logoButton, titleLabel, detailLabel, progressTrack, scrubber] + controls as [NSView] { view.isHidden = hidden }
        if !hidden { progressTrack.isHidden = (state?.duration ?? 0) == 0 }
    }

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { splashing = false; splash.isHidden = true; setContent(hidden: false); return }
        if let browser { javaScript = MediaControl.javaScriptAvailable(in: browser) }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard scrubFraction == nil, let browser else { return }
        state = javaScript ? MediaControl.state(in: browser) : nil
        render()
    }

    private func perform(_ action: MediaControl.Action) {
        guard let site, let browser else { return }
        let resolved: MediaControl.Action = action == .next && (state?.canSkip ?? (site == .netflix)) ? .skip : action
        MediaControl.perform(resolved, site: site, in: browser)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.refresh() }
    }

    private func render() {
        guard let site else { return }
        let windowTitle = site.cleanTitle(MediaSiteMonitor.shared.title)
        let fallback = windowTitle.isEmpty ? site.name : windowTitle
        titleLabel.stringValue = (state?.title).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        loadArtwork(state?.artwork)
        if let state {
            let position = scrubFraction.map { Double($0) * state.duration } ?? state.time
            var parts: [String] = []
            if state.ad { parts.append("Ad") }
            if !state.subtitle.isEmpty, !state.ad { parts.append(state.subtitle) }
            if state.duration > 0 {
                parts.append(scrubFraction == nil
                    ? "-" + Spotify.format(Int(state.duration - position))
                    : Spotify.format(Int(position)) + " / " + Spotify.format(Int(state.duration)))
            }
            parts.append("\(Int((state.volume * 100).rounded()))%")
            detailLabel.stringValue = parts.joined(separator: "  ·  ")
            play.image = NSImage(systemSymbolName: state.playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)
            skip.image = NSImage(systemSymbolName: state.canSkip ? "forward.end.alt.fill" : "forward.end.fill", accessibilityDescription: nil)
            skip.toolTip = state.canSkip ? "Skip" : "Next"
        } else {
            let browserName = browser?.localizedName ?? "your browser"
            let menu = browser?.bundleIdentifier == "com.apple.Safari" ? "Develop" : "View › Developer"
            detailLabel.stringValue = browser?.bundleIdentifier == "org.mozilla.firefox"
                ? "Using \(site.name) keyboard shortcuts"
                : "For live time, enable \(menu) › Allow JavaScript from Apple Events in \(browserName)"
            play.image = NSImage(systemSymbolName: "playpause.fill", accessibilityDescription: nil)
        }
        let rate = state?.rate ?? 1
        speed.setTitle(rate == 1 ? "1×" : String(format: "%g×", rate), size: 12, weight: .semibold)
        if !splashing { progressTrack.isHidden = (state?.duration ?? 0) == 0 }
        needsLayout = true
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        guard let url else { artwork.image = nil; artwork.isHidden = true; needsLayout = true; return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async {
                guard let self, self.artworkURL == url else { return }
                self.artwork.image = image
                self.artwork.isHidden = image == nil
                self.needsLayout = true
            }
        }.resume()
    }

    private func scrub(to x: CGFloat, done: Bool) {
        guard let state, state.duration > 0, let browser else { return }
        let local = x + scrubber.frame.minX - progressTrack.frame.minX
        let fraction = min(1, max(0, local / max(1, progressTrack.frame.width)))
        if done {
            scrubFraction = nil
            self.state?.time = Double(fraction) * state.duration
            MediaControl.seek(toFraction: Double(fraction), in: browser)
        } else {
            scrubFraction = fraction
        }
        render()
    }

    override func layout() {
        super.layout()
        let size: CGFloat = 36
        let controlsWidth = CGFloat(controls.count) * (size + Glass.gap) - Glass.gap
        var buttonX = bounds.width - controlsWidth
        for button in controls {
            button.frame = NSRect(x: buttonX, y: 0, width: size, height: bounds.height)
            buttonX += size + Glass.gap
        }
        let hasArt = !artwork.isHidden
        logoButton.frame = NSRect(x: 0, y: 0, width: hasArt ? 52 : 40, height: bounds.height)
        artwork.frame = logoButton.bounds.insetBy(dx: 2, dy: 2)
        logo.frame = hasArt
            ? NSRect(x: logoButton.bounds.maxX - (site == .netflix ? 9 : 15), y: 3, width: site == .netflix ? 6 : 12, height: site == .netflix ? 10 : 8)
            : logoButton.bounds.insetBy(dx: 7, dy: 8)
        let x = logoButton.frame.maxX + 8
        let textWidth = max(0, bounds.width - controlsWidth - 10 - x)
        titleLabel.frame = NSRect(x: x, y: bounds.height - 16, width: textWidth, height: 15)
        detailLabel.frame = NSRect(x: x, y: 5, width: textWidth, height: 12)
        let thick: CGFloat = scrubFraction == nil ? 3 : 5
        progressTrack.frame = NSRect(x: x, y: 0.5, width: textWidth, height: thick)
        progressTrack.layer?.cornerRadius = thick / 2
        progressFill.layer?.cornerRadius = thick / 2
        let fraction = scrubFraction ?? (state.map { $0.duration > 0 ? CGFloat($0.time / $0.duration) : 0 } ?? 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressFill.frame = NSRect(x: 0, y: 0, width: progressTrack.bounds.width * min(1, max(0, fraction)), height: thick)
        CATransaction.commit()
        scrubber.frame = NSRect(x: x, y: 0, width: textWidth, height: bounds.height)

        splash.frame = bounds
        splashLabel.sizeToFit()
        let logoWidth: CGFloat = site == .netflix ? 14 : 34
        let total = logoWidth + 10 + splashLabel.frame.width
        let startX = (bounds.width - total) / 2
        splashLogo.frame = NSRect(x: startX, y: (bounds.height - 24) / 2, width: logoWidth, height: 24)
        splashLabel.frame.origin = NSPoint(x: startX + logoWidth + 10, y: (bounds.height - splashLabel.frame.height) / 2)
    }
}
