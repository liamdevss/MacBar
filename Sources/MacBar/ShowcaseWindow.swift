import AppKit
import Carbon.HIToolbox

final class ShowcaseWindowController: NSWindowController, NSWindowDelegate {
    private var monitor: Any?
    private let showcase: ShowcaseView

    init(store: LauncherStore) {
        showcase = ShowcaseView(store: store)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: showcase.frame.size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "MacBar Showcase"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = showcase
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        showcase.launcher.update(store: showcase.store)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                self?.showcase.keyEvent(event)
                return event
            }
        }
        showcase.launcher.playIntro()
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        showcase.launcher.closeGame()
    }
}

final class ShowcaseView: NSView {
    private struct Key {
        var label: String
        var top: String? = nil
        var code: Int?
        var width: CGFloat = 1
        var small = false
    }

    let store: LauncherStore
    let launcher = LauncherBarView(frame: NSRect(x: 0, y: 0, width: TouchBarController.barWidth, height: 30))
    private var pressed: Set<Int> = []
    private let replay = GlassButton()
    private let hint = NSTextField(labelWithString: "Click the bar to use it  ·  ⌘⇧5 to record")

    private static let unit: CGFloat = 74
    private static let rowWidth: CGFloat = unit * 14.5
    private static let keyGap: CGFloat = 6
    private static let margin: CGFloat = 44

    private static let rows: [[Key]] = [
        [Key(label: "`", top: "~", code: kVK_ANSI_Grave)] +
            zip(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
                ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"]).enumerated().map { index, pair in
                Key(label: pair.0, top: pair.1, code: [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
                                                     kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0, kVK_ANSI_Minus, kVK_ANSI_Equal][index])
            } + [Key(label: "delete", code: kVK_Delete, width: 1.5, small: true)],
        [Key(label: "tab", code: kVK_Tab, width: 1.5, small: true)] +
            letters("QWERTYUIOP", [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P]) +
            [Key(label: "[", top: "{", code: kVK_ANSI_LeftBracket), Key(label: "]", top: "}", code: kVK_ANSI_RightBracket),
             Key(label: "\\", top: "|", code: kVK_ANSI_Backslash)],
        [Key(label: "caps lock", code: kVK_CapsLock, width: 1.75, small: true)] +
            letters("ASDFGHJKL", [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L]) +
            [Key(label: ";", top: ":", code: kVK_ANSI_Semicolon), Key(label: "'", top: "\"", code: kVK_ANSI_Quote),
             Key(label: "return", code: kVK_Return, width: 1.75, small: true)],
        [Key(label: "shift", code: kVK_Shift, width: 2.25, small: true)] +
            letters("ZXCVBNM", [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M]) +
            [Key(label: ",", top: "<", code: kVK_ANSI_Comma), Key(label: ".", top: ">", code: kVK_ANSI_Period),
             Key(label: "/", top: "?", code: kVK_ANSI_Slash), Key(label: "shift", code: kVK_RightShift, width: 2.25, small: true)],
        [Key(label: "fn", code: kVK_Function, small: true), Key(label: "control", top: "⌃", code: kVK_Control, small: true),
         Key(label: "option", top: "⌥", code: kVK_Option, small: true),
         Key(label: "command", top: "⌘", code: kVK_Command, width: 1.25, small: true),
         Key(label: "", code: kVK_Space, width: 5),
         Key(label: "command", top: "⌘", code: kVK_RightCommand, width: 1.25, small: true),
         Key(label: "option", top: "⌥", code: kVK_RightOption, small: true)]
    ]

    private static func letters(_ text: String, _ codes: [Int]) -> [Key] {
        zip(text, codes).map { Key(label: String($0), code: $1) }
    }

    init(store: LauncherStore) {
        self.store = store
        let height = Self.margin * 2 + 34 + 12 + Self.unit * 5 + 150
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth + Self.margin * 2, height: height))
        launcher.update(store: store)
        addSubview(launcher)
        replay.setTitle("Replay Welcome")
        replay.onPress = { [weak self] in self?.launcher.playIntro() }
        addSubview(replay)
        hint.textColor = NSColor.white.withAlphaComponent(0.45)
        hint.font = .systemFont(ofSize: 12)
        addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func keyEvent(_ event: NSEvent) {
        let code = Int(event.keyCode)
        switch event.type {
        case .keyDown: pressed.insert(code)
        case .keyUp: pressed.remove(code)
        case .flagsChanged: if pressed.contains(code) { pressed.remove(code) } else { pressed.insert(code) }
        default: break
        }
        needsDisplay = true
    }

    private var touchBarRect: NSRect {
        NSRect(x: Self.margin, y: bounds.height - Self.margin - 34, width: Self.rowWidth, height: 34)
    }

    override func layout() {
        super.layout()
        let bar = touchBarRect
        launcher.frame = NSRect(x: bar.maxX - TouchBarController.barWidth - 2, y: bar.minY + 2,
                                width: TouchBarController.barWidth, height: 30)
        replay.frame = NSRect(x: bounds.midX - 70, y: 18, width: 140, height: 28)
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: bounds.midX - hint.frame.width / 2, y: 52)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.245, blue: 0.26, alpha: 1),
                            NSColor(srgbRed: 0.17, green: 0.175, blue: 0.19, alpha: 1)])!.draw(in: bounds, angle: -90)

        let bar = touchBarRect
        let strip = NSBezierPath(roundedRect: bar, xRadius: 7, yRadius: 7)
        NSColor.black.setFill()
        strip.fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        strip.lineWidth = 1
        strip.stroke()
        let escRect = NSRect(x: bar.minX + 4, y: bar.minY + 3, width: bar.width - TouchBarController.barWidth - 12, height: bar.height - 6)
        NSColor(white: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: escRect, xRadius: 6, yRadius: 6).fill()
        drawCentered("esc", in: escRect, size: 12, alpha: 0.75)

        var y = bar.minY - 12 - Self.unit
        for row in Self.rows {
            var x = Self.margin
            for key in row {
                let width = key.width * Self.unit
                drawKey(key, in: NSRect(x: x, y: y, width: width - Self.keyGap, height: Self.unit - Self.keyGap))
                x += width
            }
            if row.last?.code == kVK_RightOption { drawArrows(x: x, y: y) }
            y -= Self.unit
        }

        let padWidth = Self.unit * 6.5
        let pad = NSRect(x: bounds.midX - padWidth / 2, y: -40, width: padWidth, height: y + Self.unit - 30 + 40)
        let padPath = NSBezierPath(roundedRect: pad, xRadius: 14, yRadius: 14)
        NSGradient(colors: [NSColor(srgbRed: 0.2, green: 0.205, blue: 0.22, alpha: 1),
                            NSColor(srgbRed: 0.15, green: 0.155, blue: 0.17, alpha: 1)])!.draw(in: padPath, angle: -90)
        NSColor.black.withAlphaComponent(0.35).setStroke()
        padPath.lineWidth = 1
        padPath.stroke()
    }

    private func drawArrows(x: CGFloat, y: CGFloat) {
        let w = Self.unit - Self.keyGap, h = Self.unit - Self.keyGap, half = (h - 2) / 2
        drawKey(Key(label: "◀", code: kVK_LeftArrow, small: true), in: NSRect(x: x, y: y, width: w, height: half))
        drawKey(Key(label: "▼", code: kVK_DownArrow, small: true), in: NSRect(x: x + Self.unit, y: y, width: w, height: half))
        drawKey(Key(label: "▲", code: kVK_UpArrow, small: true), in: NSRect(x: x + Self.unit, y: y + half + 2, width: w, height: half))
        drawKey(Key(label: "▶", code: kVK_RightArrow, small: true), in: NSRect(x: x + Self.unit * 2, y: y, width: w, height: half))
    }

    private func drawKey(_ key: Key, in rect: NSRect) {
        let down = key.code.map(pressed.contains) ?? false
        let frame = down ? rect.offsetBy(dx: 0, dy: -1.5) : rect
        let path = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
        if down {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = NSColor(srgbRed: 0.9, green: 0.4, blue: 0.75, alpha: 0.9)
            glow.shadowBlurRadius = 12
            glow.set()
            NSColor(white: 0.24, alpha: 1).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSGradient(colors: [NSColor(white: 0.13, alpha: 1), NSColor(white: 0.09, alpha: 1)])!.draw(in: path, angle: -90)
        }
        NSColor.white.withAlphaComponent(down ? 0.25 : 0.07).setStroke()
        path.lineWidth = 1
        path.stroke()

        let alpha: CGFloat = down ? 1 : 0.82
        if key.small {
            if key.label.count == 1 {
                drawCentered(key.label, in: frame, size: 10, alpha: alpha)
            } else {
                drawText(key.label, at: NSPoint(x: frame.minX + 8, y: frame.minY + 7), size: 11, alpha: alpha)
                if let top = key.top {
                    drawText(top, at: NSPoint(x: frame.maxX - 20, y: frame.maxY - 22), size: 13, alpha: alpha)
                }
            }
        } else if let top = key.top {
            drawCentered(top, in: frame.insetBy(dx: 0, dy: 0).offsetBy(dx: 0, dy: 11), size: 14, alpha: alpha)
            drawCentered(key.label, in: frame.offsetBy(dx: 0, dy: -10), size: 16, alpha: alpha)
        } else {
            drawCentered(key.label, in: frame, size: 20, alpha: alpha)
        }
    }

    private func attributes(_ size: CGFloat, _ alpha: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(alpha)]
    }

    private func drawCentered(_ text: String, in rect: NSRect, size: CGFloat, alpha: CGFloat) {
        let string = NSAttributedString(string: text, attributes: attributes(size, alpha))
        let s = string.size()
        string.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, alpha: CGFloat) {
        NSAttributedString(string: text, attributes: attributes(size, alpha)).draw(at: point)
    }
}
