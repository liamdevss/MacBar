import AppKit
import AudioToolbox
import CoreAudio
import TouchBarBridge

enum SystemAudio {
    private static func defaultOutput() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func adjustVolume(by delta: Float) {
        guard let device = defaultOutput() else { return }
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return }
        volume = min(1, max(0, volume + delta))
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
        if volume > 0 { setMuted(false, device: device) }
    }

    static var volume: Float? {
        guard let device = defaultOutput() else { return nil }
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr ? volume : nil
    }

    static func setVolume(_ value: Float) {
        guard let current = volume else { return }
        adjustVolume(by: min(1, max(0, value)) - current)
    }

    static func toggleMute() {
        guard let device = defaultOutput() else { return }
        var address = address(kAudioDevicePropertyMute)
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return }
        setMuted(muted == 0, device: device)
    }

    private static func setMuted(_ muted: Bool, device: AudioDeviceID) {
        var address = address(kAudioDevicePropertyMute)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

class TouchSurface: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.direct]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func touchBegan(_ x: CGFloat) {}
    func touchMoved(_ x: CGFloat) {}
    func touchEnded(_ x: CGFloat, cancelled: Bool) {}

    private func x(_ event: NSEvent, _ phase: NSTouch.Phase) -> CGFloat? {
        event.touches(matching: phase, in: self).first?.location(in: self).x
    }
    override func touchesBegan(with event: NSEvent) { if let x = x(event, .began) { touchBegan(x) } }
    override func touchesMoved(with event: NSEvent) { if let x = x(event, .moved) { touchMoved(x) } }
    override func touchesEnded(with event: NSEvent) { if let x = x(event, .ended) { touchEnded(x, cancelled: false) } }
    override func touchesCancelled(with event: NSEvent) { touchEnded(0, cancelled: true) }
    override func mouseDown(with event: NSEvent) { touchBegan(convert(event.locationInWindow, from: nil).x) }
    override func mouseDragged(with event: NSEvent) { touchMoved(convert(event.locationInWindow, from: nil).x) }
    override func mouseUp(with event: NSEvent) { touchEnded(convert(event.locationInWindow, from: nil).x, cancelled: false) }
}

final class SystemControlsView: TouchSurface {
    private enum Kind { case brightness, volume }
    private struct Control {
        let symbol: String
        let label: String
        let kind: Kind
        let tap: () -> Void
    }
    private static let step: Float = 1 / 16
    private static let controls: [Control] = [
        Control(symbol: "sun.min.fill", label: "Brightness down", kind: .brightness) { _ = MBAdjustBrightness(-step) },
        Control(symbol: "sun.max.fill", label: "Brightness up", kind: .brightness) { _ = MBAdjustBrightness(step) },
        Control(symbol: "speaker.slash.fill", label: "Mute", kind: .volume) { SystemAudio.toggleMute() },
        Control(symbol: "speaker.wave.1.fill", label: "Volume down", kind: .volume) { SystemAudio.adjustVolume(by: -step) },
        Control(symbol: "speaker.wave.3.fill", label: "Volume up", kind: .volume) { SystemAudio.adjustVolume(by: step) }
    ]
    static let tileWidth: CGFloat = 40
    static var preferredWidth: CGFloat { CGFloat(controls.count) * (tileWidth + Glass.gap) - Glass.gap }

    private var tiles: [GlassButton] = []
    private let slider = LevelSlider()
    private var pressed: Int?
    private var startX: CGFloat = 0
    private var sliding: Kind?
    private var startValue: Float = 0
    private var holdTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        tiles = Self.controls.map { control in
            let tile = GlassButton()
            tile.image = NSImage(systemSymbolName: control.symbol, accessibilityDescription: control.label)
            tile.toolTip = control.label
            addSubview(tile)
            return tile
        }
        slider.isHidden = true
        addSubview(slider)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func touchBegan(_ x: CGFloat) {
        let index = min(tiles.count - 1, max(0, Int(x / (Self.tileWidth + Glass.gap))))
        pressed = index
        startX = x
        Glass.setPressed(tiles[index], true)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self, let pressed = self.pressed else { return }
            self.beginSliding(Self.controls[pressed].kind, at: self.startX)
        }
    }

    override func touchMoved(_ x: CGFloat) {
        guard let pressed else { return }
        if sliding == nil, abs(x - startX) > 8 { beginSliding(Self.controls[pressed].kind, at: startX) }
        guard let sliding else { return }
        let value = min(1, max(0, startValue + Float((x - startX) / slider.trackWidth)))
        apply(value, sliding)
        slider.value = CGFloat(value)
    }

    override func touchEnded(_ x: CGFloat, cancelled: Bool) {
        holdTimer?.invalidate()
        guard let index = pressed else { return }
        pressed = nil
        Glass.setPressed(tiles[index], false)
        if sliding != nil {
            sliding = nil
            slider.isHidden = true
            tiles.forEach { $0.isHidden = false; Glass.appear($0, delay: 0) }
        } else if !cancelled {
            Glass.bounce(tiles[index])
            Self.controls[index].tap()
        }
    }

    private func beginSliding(_ kind: Kind, at x: CGFloat) {
        guard sliding == nil else { return }
        holdTimer?.invalidate()
        let current: Float? = kind == .volume ? SystemAudio.volume : { let b = MBGetBrightness(); return b >= 0 ? b : nil }()
        guard let current else { return }
        sliding = kind
        startValue = current
        startX = x
        slider.symbol = kind == .volume ? "speaker.wave.2.fill" : "sun.max.fill"
        slider.value = CGFloat(current)
        tiles.forEach { $0.isHidden = true }
        if let pressed { Glass.setPressed(tiles[pressed], false) }
        slider.isHidden = false
        Glass.appear(slider, delay: 0)
    }

    private func apply(_ value: Float, _ kind: Kind) {
        switch kind {
        case .volume: SystemAudio.setVolume(value)
        case .brightness: _ = MBSetBrightness(value)
        }
    }

    override func layout() {
        super.layout()
        for (index, tile) in tiles.enumerated() {
            tile.frame = NSRect(x: CGFloat(index) * (Self.tileWidth + Glass.gap), y: 0, width: Self.tileWidth, height: bounds.height)
        }
        slider.frame = bounds
    }
}

final class LevelSlider: NSView {
    private let icon = NSImageView()
    private let track = NSView()
    private let fill = NSView()
    var symbol = "speaker.wave.2.fill" {
        didSet { icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }
    var value: CGFloat = 0 { didSet { needsLayout = true } }
    var trackWidth: CGFloat { max(1, bounds.width - 46) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Glass.style(self)
        icon.contentTintColor = .white
        icon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        addSubview(icon)
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        track.layer?.cornerRadius = 3
        fill.wantsLayer = true
        fill.layer?.backgroundColor = NSColor.white.cgColor
        fill.layer?.cornerRadius = 3
        track.addSubview(fill)
        addSubview(track)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        Glass.layoutSheen(self)
        icon.frame = NSRect(x: 8, y: bounds.midY - 10, width: 22, height: 20)
        track.frame = NSRect(x: 36, y: bounds.midY - 3, width: trackWidth, height: 6)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = NSRect(x: 0, y: 0, width: track.bounds.width * min(1, max(0, value)), height: 6)
        CATransaction.commit()
    }
}
