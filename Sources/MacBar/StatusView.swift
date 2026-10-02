import AppKit
import CoreWLAN
import IOKit.ps

enum SystemStatus {
    static func wifiSymbol() -> String {
        guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return "wifi.slash" }
        let rssi = interface.rssiValue()
        return rssi == 0 ? "wifi.exclamationmark" : "wifi"
    }

    static func battery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = (description[kIOPSIsChargingKey] as? Bool) == true
                || (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (Int((Double(current) / Double(max) * 100).rounded()), charging)
        }
        return nil
    }

    static func batterySymbol(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch percent {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }
}

final class StatusView: NSView {
    static let preferredWidth: CGFloat = 250
    private let wifi = NSImageView()
    private let batteryText = NSTextField(labelWithString: "")
    private let batteryIcon = NSImageView()
    private let clock = NSTextField(labelWithString: "")
    private var timer: Timer?
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM HH:mm"
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Glass.style(self)
        for label in [batteryText, clock] {
            label.textColor = .white
            label.font = .systemFont(ofSize: 14, weight: .regular)
            addSubview(label)
        }
        clock.alignment = .left
        batteryText.alignment = .right
        for image in [wifi, batteryIcon] {
            image.contentTintColor = .white
            image.symbolConfiguration = .init(pointSize: 15, weight: .regular)
            addSubview(image)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        refresh()
        var ticks = 0
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            ticks += 1
            if ticks % 15 == 0 { self?.refresh() } else { self?.updateClock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        wifi.image = NSImage(systemSymbolName: SystemStatus.wifiSymbol(), accessibilityDescription: "Wi-Fi")
        if let battery = SystemStatus.battery() {
            batteryText.stringValue = "\(battery.percent)%"
            batteryIcon.image = NSImage(systemSymbolName: SystemStatus.batterySymbol(percent: battery.percent, charging: battery.charging),
                                        accessibilityDescription: "Battery")
        } else {
            batteryText.stringValue = ""
            batteryIcon.image = nil
        }
        updateClock()
    }

    private func updateClock() {
        let now = Date()
        let text = NSMutableAttributedString(string: formatter.string(from: now), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.white
        ])
        let colon = (text.string as NSString).range(of: ":", options: .backwards)
        if colon.location != NSNotFound, Int(now.timeIntervalSince1970) % 2 == 1 {
            text.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.25), range: colon)
        }
        clock.attributedStringValue = text
    }

    override func layout() {
        super.layout()
        Glass.layoutSheen(self)
        let midY = bounds.midY
        wifi.frame = NSRect(x: 8, y: midY - 11, width: 24, height: 22)
        batteryText.frame = NSRect(x: 34, y: midY - 9, width: 46, height: 18)
        batteryIcon.frame = NSRect(x: 82, y: midY - 11, width: 30, height: 22)
        clock.frame = NSRect(x: 120, y: midY - 9, width: bounds.width - 124, height: 18)
    }
}
