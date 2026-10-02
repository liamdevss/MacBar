import AppKit
import SwiftUI

final class BackgroundView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var mode: BackgroundMode = .fill { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image else { return }
        let rect = Self.imageRect(imageSize: image.size, bounds: bounds, mode: mode)
        NSGraphicsContext.saveGraphicsState()
        bounds.clip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    static func imageRect(imageSize: NSSize, bounds: NSRect, mode: BackgroundMode) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, mode != .stretch else { return bounds }
        let x = bounds.width / imageSize.width
        let y = bounds.height / imageSize.height
        let scale = mode == .fill ? max(x, y) : min(x, y)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

struct BackgroundPreview: NSViewRepresentable {
    let image: NSImage?
    let mode: BackgroundMode
    func makeNSView(context: Context) -> BackgroundView { BackgroundView() }
    func updateNSView(_ view: BackgroundView, context: Context) {
        view.image = image
        view.mode = mode
    }
}
