import AppKit

enum Spotify {
    static let bundleIdentifier = "com.spotify.client"

    struct NowPlaying: Equatable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var volume: Int
        var position: Int
        var duration: Int
        var artworkURL: URL?
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    static var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "music.note", accessibilityDescription: "Spotify")!
    }

    @discardableResult
    static func run(_ command: String) -> String? {
        let script = NSAppleScript(source: "tell application id \"\(bundleIdentifier)\" to \(command)")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }

    static func previous() { run("previous track") }
    static func playPause() { run("playpause") }
    static func next() { run("next track") }
    static func seek(to seconds: Int) { run("set player position to \(max(0, seconds))") }
    static func adjustVolume(by delta: Int) {
        run("set sound volume to ((sound volume) + \(delta))")
    }

    static func nowPlaying() -> NowPlaying? {
        guard isRunning else { return nil }
        let fields = [
            "name of current track", "artist of current track", "player state as string",
            "sound volume as string", "(round (get player position)) as string",
            "(round ((get duration of current track) / 1000)) as string", "artwork url of current track"
        ]
        let script = "(" + fields.map { "(\($0))" }.joined(separator: " & linefeed & ") + ")"
        guard let raw = run(script) else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count == fields.count else { return nil }
        return NowPlaying(title: parts[0], artist: parts[1], isPlaying: parts[2] == "playing",
                          volume: Int(parts[3]) ?? 0, position: Int(parts[4]) ?? 0,
                          duration: Int(parts[5]) ?? 0, artworkURL: URL(string: parts[6]))
    }

    static func format(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

final class MarqueeLabel: NSView {
    private let first = NSTextField(labelWithString: "")
    private let second = NSTextField(labelWithString: "")
    private var timer: Timer?
    private var offset: CGFloat = 0
    private var pauseUntil = Date()
    private let spacing: CGFloat = 36

    var font: NSFont = .systemFont(ofSize: 11, weight: .semibold) { didSet { configure() } }
    var stringValue = "" {
        didSet {
            guard stringValue != oldValue else { return }
            offset = 0
            pauseUntil = Date().addingTimeInterval(1.5)
            configure()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        for label in [first, second] {
            label.textColor = .white
            addSubview(label)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var textWidth: CGFloat { first.intrinsicContentSize.width }
    private var overflows: Bool { textWidth > bounds.width }

    private func configure() {
        for label in [first, second] {
            label.font = font
            label.stringValue = stringValue
        }
        needsLayout = true
        updateTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    private func updateTimer() {
        let shouldRun = window != nil && overflows
        if !shouldRun { timer?.invalidate(); timer = nil; offset = 0; return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func step() {
        guard Date() >= pauseUntil else { return }
        offset += 1
        if offset >= textWidth + spacing {
            offset = 0
            pauseUntil = Date().addingTimeInterval(1.5)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = textWidth
        let height = first.intrinsicContentSize.height
        let y = (bounds.height - height) / 2
        first.frame = NSRect(x: -offset, y: y, width: width, height: height)
        second.frame = NSRect(x: -offset + width + spacing, y: y, width: width, height: height)
        second.isHidden = !overflows
        updateTimer()
    }
}

final class SpotifyPanelView: NSView {
    private let previousButton = GlassButton()
    private let playButton = GlassButton()
    private let nextButton = GlassButton()
    private let volumeDownButton = GlassButton()
    private let volumeUpButton = GlassButton()
    private let artwork = NSImageView()
    private let titleLabel = MarqueeLabel()
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let scrubber = ScrubSurface()
    private var controls: [GlassButton] { [previousButton, playButton, nextButton, volumeDownButton, volumeUpButton] }

    private var state: Spotify.NowPlaying?
    private var artworkURL: URL?
    private var timer: Timer?
    private var ticks = 0
    private var scrubFraction: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure(previousButton, "backward.fill", "Previous track") { Spotify.previous() }
        configure(playButton, "playpause.fill", "Play or pause") { Spotify.playPause() }
        configure(nextButton, "forward.fill", "Next track") { Spotify.next() }
        configure(volumeDownButton, "speaker.wave.1.fill", "Spotify volume down") { Spotify.adjustVolume(by: -10) }
        configure(volumeUpButton, "speaker.wave.3.fill", "Spotify volume up") { Spotify.adjustVolume(by: 10) }
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 5
        artwork.layer?.masksToBounds = true
        addSubview(artwork)
        addSubview(titleLabel)
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        progressTrack.layer?.cornerRadius = 1.5
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = NSColor.white.cgColor
        progressFill.layer?.cornerRadius = 1.5
        progressTrack.addSubview(progressFill)
        addSubview(progressTrack)
        scrubber.onScrub = { [weak self] x, done in self?.scrub(to: x, done: done) }
        scrubber.onCancel = { [weak self] in self?.scrubFraction = nil; self?.render() }
        addSubview(scrubber)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ button: GlassButton, _ symbol: String, _ label: String, _ action: @escaping () -> Void) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.toolTip = label
        button.onPress = { [weak self] in action(); self?.refreshSoon() }
        addSubview(button)
    }

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { return }
        refresh()
        for (index, view) in ([artwork] + controls).enumerated() { Glass.appear(view, delay: Double(index) * 0.03) }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setActive(window != nil && !isHidden)
    }

    private func tick() {
        ticks += 1
        guard scrubFraction == nil else { return }
        if ticks % 5 == 0 { refresh(); return }
        guard var state, state.isPlaying else { return }
        state.position = min(state.duration, state.position + 1)
        if state.duration > 0, state.position >= state.duration { refresh(); return }
        self.state = state
        render()
    }

    func refresh() {
        state = Spotify.nowPlaying()
        render()
        loadArtwork(state?.artworkURL)
    }

    private func render() {
        guard let state else {
            titleLabel.stringValue = Spotify.isRunning ? "Spotify" : "Spotify isn’t open"
            detailLabel.stringValue = Spotify.isRunning ? "Nothing playing" : "Tap ▶︎ to start"
            playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
            artwork.image = Spotify.icon
            progressTrack.isHidden = true
            return
        }
        titleLabel.stringValue = state.title
        let position = scrubFraction.map { Int($0 * CGFloat(state.duration)) } ?? state.position
        let time = scrubFraction == nil
            ? "-" + Spotify.format(state.duration - position)
            : Spotify.format(position) + " / " + Spotify.format(state.duration)
        detailLabel.stringValue = state.artist.isEmpty ? time : "\(time)  ·  \(state.artist)  ·  \(state.volume)%"
        playButton.image = NSImage(systemSymbolName: state.isPlaying ? "pause.fill" : "play.fill",
                                   accessibilityDescription: state.isPlaying ? "Pause" : "Play")
        progressTrack.isHidden = state.duration == 0
        needsLayout = true
    }

    private func scrub(to x: CGFloat, done: Bool) {
        guard let state, state.duration > 0 else { return }
        let local = x + scrubber.frame.minX - progressTrack.frame.minX
        let fraction = min(1, max(0, local / max(1, progressTrack.frame.width)))
        if done {
            scrubFraction = nil
            self.state?.position = Int(fraction * CGFloat(state.duration))
            Spotify.seek(to: Int(fraction * CGFloat(state.duration)))
            refreshSoon()
        } else {
            scrubFraction = fraction
        }
        render()
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkURL else { return }
        artworkURL = url
        guard let url else { artwork.image = Spotify.icon; return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async {
                guard let self, self.artworkURL == url else { return }
                self.artwork.image = image ?? Spotify.icon
            }
        }.resume()
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.refresh() }
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
        artwork.frame = NSRect(x: 0, y: (bounds.height - 28) / 2, width: 28, height: 28)
        let x = artwork.frame.maxX + 8
        let textWidth = max(0, bounds.width - controlsWidth - 10 - x)
        titleLabel.frame = NSRect(x: x, y: bounds.height - 16, width: textWidth, height: 15)
        detailLabel.frame = NSRect(x: x, y: 5, width: textWidth, height: 12)
        let thick: CGFloat = scrubFraction == nil ? 3 : 5
        progressTrack.frame = NSRect(x: x, y: 0.5, width: textWidth, height: thick)
        progressTrack.layer?.cornerRadius = thick / 2
        progressFill.layer?.cornerRadius = thick / 2
        let fraction = scrubFraction ?? (state.map { $0.duration > 0 ? CGFloat($0.position) / CGFloat($0.duration) : 0 } ?? 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressFill.frame = NSRect(x: 0, y: 0, width: progressTrack.bounds.width * min(1, max(0, fraction)), height: thick)
        CATransaction.commit()
        scrubber.frame = NSRect(x: 0, y: 0, width: x + textWidth, height: bounds.height)
    }
}

final class ScrubSurface: TouchSurface {
    var onScrub: ((CGFloat, Bool) -> Void)?
    var onCancel: (() -> Void)?
    private var startX: CGFloat = 0
    private var scrubbing = false

    override func touchBegan(_ x: CGFloat) { startX = x; scrubbing = false }
    override func touchMoved(_ x: CGFloat) {
        if !scrubbing, abs(x - startX) > 6 { scrubbing = true }
        if scrubbing { onScrub?(x, false) }
    }
    override func touchEnded(_ x: CGFloat, cancelled: Bool) {
        if scrubbing { cancelled ? onCancel?() : onScrub?(x, true) }
        scrubbing = false
    }
}
