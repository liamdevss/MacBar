import AppKit
import Carbon.HIToolbox

final class FlappyGameView: TouchSurface {
    private enum State { case ready, playing, dead }
    private struct Pipe {
        var x: CGFloat
        var gapY: CGFloat
        var scored = false
    }

    var onExit: (() -> Void)?
    private let closeButton = GlassButton()
    private let background: NSImage?
    private let mode: BackgroundMode

    private var state = State.ready
    private var birdY: CGFloat = 15
    private var velocity: CGFloat = 0
    private var pipes: [Pipe] = []
    private var score = 0
    private var best = UserDefaults.standard.integer(forKey: "flappy.best")
    private var newBest = false
    private var time: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var diedAt: CFTimeInterval = 0
    private var flapAt: CFTimeInterval = -1
    private var timer: Timer?
    private let stars: [(x: CGFloat, y: CGFloat, depth: CGFloat)] = (0..<70).map { _ in
        (CGFloat.random(in: 0...1100), CGFloat.random(in: 2...28), CGFloat.random(in: 0.2...1))
    }

    private let birdX: CGFloat = 96
    private let gravity: CGFloat = 80
    private let flapVelocity: CGFloat = 29
    private let maxFallSpeed: CGFloat = 42
    private let pipeWidth: CGFloat = 16
    private let gapHeight: CGFloat = 18
    private let pipeSpacing: CGFloat = 210
    private var speed: CGFloat { min(145, 90 + CGFloat(score) * 1.5) }

    init(frame: NSRect, background: NSImage?, mode: BackgroundMode) {
        self.background = background
        self.mode = mode
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Quit Flappy Bar")
        closeButton.onPress = { [weak self] in self?.onExit?() }
        addSubview(closeButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start() {
        reset()
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func reset() {
        state = .ready
        birdY = bounds.midY
        velocity = 0
        score = 0
        newBest = false
        pipes = []
    }

    func flap() {
        switch state {
        case .ready:
            state = .playing
            pipes = [Pipe(x: bounds.width + 20, gapY: randomGap())]
            fallthrough
        case .playing:
            velocity = flapVelocity
            flapAt = time
        case .dead:
            if time - diedAt > 0.6 { reset() }
        }
    }

    override func touchBegan(_ x: CGFloat) { flap() }

    private func randomGap() -> CGFloat {
        CGFloat.random(in: (gapHeight / 2 + 2)...(bounds.height - gapHeight / 2 - 2))
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(1.0 / 30, now - lastTick)
        lastTick = now
        time += dt
        let step = CGFloat(dt)
        switch state {
        case .ready:
            birdY = bounds.midY + sin(CGFloat(time) * 4) * 2.5
        case .playing:
            velocity = max(-maxFallSpeed, velocity - gravity * step)
            birdY += velocity * step
            if birdY > bounds.height - 4 { birdY = bounds.height - 4; velocity = min(0, velocity) }
            for index in pipes.indices {
                pipes[index].x -= speed * step
                if !pipes[index].scored, pipes[index].x + pipeWidth < birdX {
                    pipes[index].scored = true
                    score += 1
                }
            }
            pipes.removeAll { $0.x < -pipeWidth - 10 }
            if let last = pipes.last, last.x < bounds.width - pipeSpacing {
                pipes.append(Pipe(x: bounds.width + 10, gapY: randomGap()))
            }
            if birdY < 2 || pipes.contains(where: collides) { die() }
        case .dead:
            velocity -= gravity * step
            birdY = max(-10, birdY + velocity * step)
        }
        needsDisplay = true
    }

    private func collides(_ pipe: Pipe) -> Bool {
        let bird = NSRect(x: birdX - 3.5, y: birdY - 2.5, width: 7, height: 5)
        guard bird.maxX > pipe.x, bird.minX < pipe.x + pipeWidth else { return false }
        return bird.minY < pipe.gapY - gapHeight / 2 || bird.maxY > pipe.gapY + gapHeight / 2
    }

    private func die() {
        state = .dead
        diedAt = time
        velocity = 20
        if score > best {
            best = score
            newBest = true
            UserDefaults.standard.set(best, forKey: "flappy.best")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        let sinceDeath = time - diedAt
        let shake: CGFloat = state == .dead && sinceDeath < 0.3 ? CGFloat(sin(sinceDeath * 90) * 3 * (1 - sinceDeath / 0.3)) : 0
        NSGraphicsContext.saveGraphicsState()
        let shift = NSAffineTransform()
        shift.translateX(by: shake, yBy: 0)
        shift.concat()

        if let background {
            background.draw(in: BackgroundView.imageRect(imageSize: background.size, bounds: bounds, mode: mode),
                            from: .zero, operation: .sourceOver, fraction: 0.45)
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        drawStars()
        pipes.forEach(drawPipe)
        drawBird()
        NSGraphicsContext.restoreGraphicsState()

        if state == .dead, sinceDeath < 0.25 {
            NSColor.systemRed.withAlphaComponent(0.35 * (1 - sinceDeath / 0.25)).setFill()
            bounds.fill()
        }
        drawHUD()
    }

    private func drawStars() {
        let drift = state == .dead ? 0 : CGFloat(time) * 18
        for star in stars {
            let x = (star.x - drift * star.depth).truncatingRemainder(dividingBy: 1100)
            let wrapped = x < 0 ? x + 1100 : x
            NSColor.white.withAlphaComponent(0.25 + 0.5 * star.depth).setFill()
            let size = 0.8 + star.depth * 0.9
            NSBezierPath(ovalIn: NSRect(x: wrapped, y: star.y, width: size, height: size)).fill()
        }
    }

    private func drawPipe(_ pipe: Pipe) {
        let gapTop = pipe.gapY + gapHeight / 2, gapBottom = pipe.gapY - gapHeight / 2
        let body = NSGradient(colors: [NSColor(srgbRed: 0.35, green: 0.85, blue: 0.45, alpha: 1),
                                       NSColor(srgbRed: 0.6, green: 0.95, blue: 0.6, alpha: 1),
                                       NSColor(srgbRed: 0.18, green: 0.6, blue: 0.3, alpha: 1)])!
        for (rect, cap) in [(NSRect(x: pipe.x, y: gapTop, width: pipeWidth, height: bounds.height - gapTop),
                             NSRect(x: pipe.x - 2, y: gapTop, width: pipeWidth + 4, height: 4)),
                            (NSRect(x: pipe.x, y: 0, width: pipeWidth, height: gapBottom),
                             NSRect(x: pipe.x - 2, y: gapBottom - 4, width: pipeWidth + 4, height: 4))] {
            guard rect.height > 0 else { continue }
            body.draw(in: rect, angle: 0)
            let capPath = NSBezierPath(roundedRect: cap, xRadius: 1.5, yRadius: 1.5)
            body.draw(in: capPath, angle: 0)
            NSColor(srgbRed: 0.1, green: 0.35, blue: 0.15, alpha: 0.9).setStroke()
            capPath.lineWidth = 0.5
            capPath.stroke()
        }
    }

    private func drawBird() {
        NSGraphicsContext.saveGraphicsState()
        let tilt = max(-55, min(30, velocity * 0.7))
        let transform = NSAffineTransform()
        transform.translateX(by: birdX, yBy: birdY)
        transform.rotate(byDegrees: tilt)
        transform.concat()
        let body = NSBezierPath(ovalIn: NSRect(x: -5.5, y: -4.5, width: 11, height: 9))
        NSGradient(colors: [NSColor(srgbRed: 1, green: 0.9, blue: 0.35, alpha: 1),
                            NSColor(srgbRed: 1, green: 0.7, blue: 0.15, alpha: 1)])!.draw(in: body, angle: -90)
        NSColor(srgbRed: 0.75, green: 0.45, blue: 0.05, alpha: 1).setStroke()
        body.lineWidth = 0.6
        body.stroke()
        let flapping = time - flapAt < 0.25 || state == .ready
        let wingY: CGFloat = flapping && Int(time * 24) % 2 == 0 ? 0.5 : -1.8
        NSColor(srgbRed: 1, green: 0.97, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: -4.5, y: wingY - 1.5, width: 5, height: 3)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 0, width: 3.6, height: 3.6)).fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2.6, y: 0.9, width: 1.5, height: 1.8)).fill()
        NSColor(srgbRed: 1, green: 0.45, blue: 0.2, alpha: 1).setFill()
        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: 4, y: 0.4))
        beak.line(to: NSPoint(x: 8, y: -0.8))
        beak.line(to: NSPoint(x: 4, y: -2.2))
        beak.close()
        beak.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .semibold, alpha: CGFloat = 1) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha)
        ])
    }

    private func drawHUD() {
        let scoreText = text("\(score)", size: 17, weight: .bold)
        let bestText = text(newBest ? "NEW BEST" : "BEST \(best)", size: 9, weight: .bold, alpha: newBest ? 1 : 0.6)
        let right = bounds.width - 12
        scoreText.draw(at: NSPoint(x: right - scoreText.size().width, y: (bounds.height - scoreText.size().height) / 2))
        bestText.draw(at: NSPoint(x: right - scoreText.size().width - 8 - bestText.size().width,
                                  y: (bounds.height - bestText.size().height) / 2))

        let message: NSAttributedString?
        switch state {
        case .ready:
            let pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(CGFloat(time) * 3))
            message = text("FLAPPY BAR  ·  tap or press space to flap", size: 12, alpha: pulse)
        case .dead where time - diedAt > 0.6:
            message = text("Game over  ·  \(score) point\(score == 1 ? "" : "s")  ·  tap to retry", size: 12)
        default:
            message = nil
        }
        if let message {
            let size = message.size()
            let rect = NSRect(x: (bounds.width - size.width) / 2 - 12, y: 3, width: size.width + 24, height: bounds.height - 6)
            NSColor.black.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: rect, xRadius: Glass.radius, yRadius: Glass.radius).fill()
            message.draw(at: NSPoint(x: rect.minX + 12, y: (bounds.height - size.height) / 2))
        }
    }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 4, y: 0, width: 36, height: bounds.height)
    }
}

final class FlappyKeyboard {
    static let shared = FlappyKeyboard()
    private var panel: NSPanel?
    private var monitor: Any?

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    func begin(onFlap: @escaping () -> Void, onExit: @escaping () -> Void) {
        end()
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 38),
                             styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let effect = NSVisualEffectView(frame: panel.contentLayoutRect)
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 19
        effect.layer?.masksToBounds = true
        let label = NSTextField(labelWithString: "🐤  Flappy Bar  ·  Space to flap  ·  Esc to quit")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 10, width: 330, height: 18)
        effect.addSubview(label)
        panel.contentView = effect
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 165, y: screen.visibleFrame.minY + 24))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Space, kVK_UpArrow:
                if !event.isARepeat { onFlap() }
                return nil
            case kVK_Escape:
                onExit()
                return nil
            default:
                return event
            }
        }
    }

    func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
