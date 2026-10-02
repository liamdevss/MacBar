import AppKit
import QuartzCore

enum Glass {
    static let radius: CGFloat = 7
    static let gap: CGFloat = 6

    static func style(_ view: NSView, prominent: Bool = false) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.backgroundColor = (prominent ? NSColor.white.withAlphaComponent(0.92) : NSColor.black.withAlphaComponent(0.34)).cgColor
        layer.borderWidth = 0.5
        layer.borderColor = NSColor.white.withAlphaComponent(prominent ? 0.6 : 0.2).cgColor
        let sheen = layer.sublayers?.first { $0.name == "glass.sheen" } as? CAGradientLayer ?? {
            let gradient = CAGradientLayer()
            gradient.name = "glass.sheen"
            layer.addSublayer(gradient)
            return gradient
        }()
        sheen.colors = [NSColor.white.withAlphaComponent(prominent ? 0 : 0.14).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        sheen.startPoint = CGPoint(x: 0.5, y: 1)
        sheen.endPoint = CGPoint(x: 0.5, y: 0.45)
        sheen.cornerRadius = radius
        sheen.cornerCurve = .continuous
        sheen.frame = layer.bounds
    }

    static func layoutSheen(_ view: NSView) {
        guard let layer = view.layer, let sheen = layer.sublayers?.first(where: { $0.name == "glass.sheen" }) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheen.frame = layer.bounds
        CATransaction.commit()
    }

    static func setPressed(_ view: NSView, _ pressed: Bool) {
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(pressed ? 0.6 : 0.34).cgColor
    }

    static func bounce(_ view: NSView) {
        guard let layer = view.layer else { return }
        let w = view.bounds.width / 2, h = view.bounds.height / 2
        func scaled(_ s: CGFloat) -> NSValue {
            var m = CATransform3DMakeTranslation(w, h, 0)
            m = CATransform3DScale(m, s, s, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(m, -w, -h, 0))
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [scaled(1), scaled(0.84), scaled(1.06), scaled(0.98), scaled(1)]
        animation.keyTimes = [0, 0.3, 0.6, 0.82, 1]
        animation.duration = 0.32
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeOut), count: 4)
        layer.add(animation, forKey: "bounce")
    }

    static func appear(_ view: NSView, delay: CFTimeInterval) {
        guard let layer = view.layer else { return }
        let begin = CACurrentMediaTime() + delay
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let slide = CABasicAnimation(keyPath: "transform")
        slide.fromValue = NSValue(caTransform3D: CATransform3DMakeTranslation(10, 0, 0))
        slide.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        for animation in [fade, slide] {
            animation.beginTime = begin
            animation.duration = 0.2
            animation.fillMode = .backwards
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "appear.\(animation.keyPath!)")
        }
    }
}

class GlassButton: NSButton {
    var onPress: (() -> Void)?
    var prominent = false { didSet { Glass.style(self, prominent: prominent) } }
    var isActive = false { didSet { restoreBackground() } }

    init() {
        super.init(frame: .zero)
        title = ""
        target = self
        action = #selector(pressed)
        isBordered = false
        contentTintColor = .white
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        Glass.style(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .medium) {
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: prominent ? NSColor.black : NSColor.white
        ])
        imagePosition = image == nil ? .noImage : .imageLeading
        imageHugsTitle = true
    }

    func fittingWidth(padding: CGFloat = 12) -> CGFloat {
        let imageWidth = image.map { $0.size.width + 5 } ?? 0
        return ceil(attributedTitle.size().width + imageWidth + padding * 2)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        if flag, !prominent { Glass.setPressed(self, true) } else { restoreBackground() }
    }

    private func restoreBackground() {
        guard !prominent else { return }
        layer?.backgroundColor = isActive
            ? NSColor.white.withAlphaComponent(0.24).cgColor
            : NSColor.black.withAlphaComponent(0.34).cgColor
    }

    @objc private func pressed() {
        Glass.bounce(self)
        onPress?()
    }

    override func layout() {
        super.layout()
        Glass.layoutSheen(self)
    }
}

final class AppButton: GlassButton {
    var badge: String? { didSet { if badge != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let badge, !badge.isEmpty else { return }
        let text = NSAttributedString(string: badge, attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: NSColor.white
        ])
        let size = text.size()
        let width = max(13, size.width + 7)
        let rect = NSRect(x: bounds.maxX - width - 1, y: bounds.maxY - 14, width: width, height: 13)
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6.5, yRadius: 6.5).fill()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }
}
