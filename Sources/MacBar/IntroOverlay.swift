import AppKit
import QuartzCore

final class IntroOverlay: NSView {
    static let greeting: [(String, Bool)] = [("Welcome", false), ("Liam,", true), ("ready", false), ("to", false), ("work!", false)]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    static let duration: CFTimeInterval = 3.1

    func play(background: NSImage?, gravity: CALayerContentsGravity, completion: @escaping () -> Void) {
        guard let root = layer else { return completion() }
        let scale = window?.backingScaleFactor ?? 2
        let start = CACurrentMediaTime() + 0.35

        if let image = background?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let backdrop = CALayer()
            backdrop.contents = image
            backdrop.contentsGravity = gravity
            backdrop.frame = bounds
            backdrop.opacity = 0
            root.addSublayer(backdrop)
            animate(backdrop, "opacity", from: 0, to: 0.75, at: start + 0.15, duration: 1.4, fill: true, ease: .easeInEaseOut)
            animate(backdrop, "transform.scale", from: 1.12, to: 1, at: start + 0.15, duration: 2.6, fill: true, ease: .easeOut)
            let scrim = CAGradientLayer()
            scrim.colors = [0.1, 0.6, 0.6, 0.1].map { NSColor.black.withAlphaComponent($0).cgColor }
            scrim.locations = [0, 0.3, 0.7, 1]
            scrim.startPoint = CGPoint(x: 0, y: 0.5)
            scrim.endPoint = CGPoint(x: 1, y: 0.5)
            scrim.frame = bounds
            root.addSublayer(scrim)
        }

        let line = CAGradientLayer()
        line.colors = [NSColor(srgbRed: 1, green: 0.45, blue: 0.55, alpha: 1).cgColor,
                       NSColor(srgbRed: 0.85, green: 0.3, blue: 0.75, alpha: 1).cgColor,
                       NSColor(srgbRed: 0.4, green: 0.4, blue: 1, alpha: 1).cgColor]
        line.startPoint = CGPoint(x: 0, y: 0.5)
        line.endPoint = CGPoint(x: 1, y: 0.5)
        line.frame = CGRect(x: bounds.width * 0.15, y: bounds.midY - 1, width: bounds.width * 0.7, height: 2)
        line.cornerRadius = 1
        line.shadowColor = NSColor(srgbRed: 0.9, green: 0.35, blue: 0.7, alpha: 1).cgColor
        line.shadowRadius = 6
        line.shadowOpacity = 0.9
        line.shadowOffset = .zero
        root.addSublayer(line)
        animate(line, "transform.scale.x", from: 0.001, to: 1, at: start, duration: 0.55, ease: .easeOut)
        animate(line, "opacity", from: 1, to: 0, at: start + 0.6, duration: 0.35, fill: true)
        animate(line, "transform.translation.y", from: 0, to: -9, at: start + 0.6, duration: 0.45, fill: true, ease: .easeIn)

        let words = Self.greeting.map { text, emphasised -> CATextLayer in
            let layer = CATextLayer()
            layer.string = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: emphasised ? .bold : .medium),
                .foregroundColor: emphasised ? NSColor.white : NSColor.white.withAlphaComponent(0.82)
            ])
            layer.contentsScale = scale
            layer.alignmentMode = .left
            return layer
        }
        let space: CGFloat = 5
        let avatarSize: CGFloat = 24, avatarGap: CGFloat = 9
        let sizes = words.map { ($0.string as! NSAttributedString).size() }
        let textWidth = sizes.reduce(0) { $0 + ceil($1.width) } + space * CGFloat(words.count - 1)
        let total = avatarSize + avatarGap + textWidth
        let groupX = (bounds.width - total) / 2

        let avatarFrame = CGRect(x: groupX, y: (bounds.height - avatarSize) / 2, width: avatarSize, height: avatarSize)
        let ring = CALayer()
        ring.frame = avatarFrame
        ring.cornerRadius = avatarSize / 2
        ring.borderWidth = 1.5
        ring.borderColor = NSColor(srgbRed: 0.95, green: 0.4, blue: 0.75, alpha: 1).cgColor
        ring.opacity = 0
        root.addSublayer(ring)
        keyframes(ring, "opacity", values: [0, 0.9, 0], times: [0, 0.15, 1], at: start + 0.75, duration: 0.8)
        keyframes(ring, "transform.scale", values: [1, 1, 1.9], times: [0, 0.15, 1], at: start + 0.75, duration: 0.8)
        let avatar = CALayer()
        avatar.contents = ProfileLink.photo.cgImage(forProposedRect: nil, context: nil, hints: nil)
        avatar.contentsGravity = .resizeAspectFill
        avatar.frame = avatarFrame
        avatar.cornerRadius = avatarSize / 2
        avatar.masksToBounds = true
        avatar.borderWidth = 1
        avatar.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        avatar.opacity = 0
        root.addSublayer(avatar)
        animate(avatar, "opacity", from: 0, to: 1, at: start + 0.55, duration: 0.25, fill: true)
        keyframes(avatar, "transform.scale", values: [0.2, 1.14, 0.96, 1], times: [0, 0.55, 0.8, 1], at: start + 0.55, duration: 0.6)

        var x = groupX + avatarSize + avatarGap
        for (index, (word, size)) in zip(words, sizes).enumerated() {
            word.frame = CGRect(x: x, y: (bounds.height - ceil(size.height)) / 2, width: ceil(size.width) + 1, height: ceil(size.height))
            x += ceil(size.width) + space
            word.opacity = 0
            root.addSublayer(word)
            let at = start + 0.7 + Double(index) * 0.11
            animate(word, "opacity", from: 0, to: 1, at: at, duration: 0.45, fill: true, ease: .easeOut)
            animate(word, "transform.translation.y", from: -8, to: 0, at: at, duration: 0.55, ease: .easeOut)
            animate(word, "transform.scale", from: 0.94, to: 1, at: at, duration: 0.55, ease: .easeOut)
        }

        let glint = CAGradientLayer()
        glint.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                        NSColor.white.withAlphaComponent(0.22).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        glint.startPoint = CGPoint(x: 0, y: 0.5)
        glint.endPoint = CGPoint(x: 1, y: 0.5)
        glint.frame = CGRect(x: 0, y: 0, width: 90, height: bounds.height)
        glint.opacity = 0
        root.addSublayer(glint)
        let sweepStart = (bounds.width - total) / 2 - 90
        animate(glint, "position.x", from: sweepStart, to: sweepStart + total + 180, at: start + 1.55, duration: 0.75, ease: .easeInEaseOut)
        animate(glint, "opacity", from: 1, to: 1, at: start + 1.55, duration: 0.75)

        animate(root, "opacity", from: 1, to: 0, at: start + 2.45, duration: 0.45, fill: true, ease: .easeIn)
        for layer in words + [avatar] {
            animate(layer, "transform.translation.y", from: 0, to: 6, at: start + 2.45, duration: 0.45, fill: true, ease: .easeIn)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { completion() }
    }

    private func keyframes(_ layer: CALayer, _ keyPath: String, values: [CGFloat], times: [NSNumber],
                           at time: CFTimeInterval, duration: CFTimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.beginTime = time
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.fillMode = .backwards
        layer.add(animation, forKey: "\(keyPath).\(time)")
    }

    private func animate(_ layer: CALayer, _ keyPath: String, from: CGFloat, to: CGFloat, at time: CFTimeInterval,
                         duration: CFTimeInterval, fill: Bool = false, ease: CAMediaTimingFunctionName = .linear) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = time
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: ease)
        animation.fillMode = fill ? .both : .backwards
        animation.isRemovedOnCompletion = !fill
        layer.add(animation, forKey: "\(keyPath).\(time)")
    }
}
