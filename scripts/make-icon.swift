import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    let body = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.04, blue: 0.09, alpha: 1),
                        NSColor(srgbRed: 0.16, green: 0.11, blue: 0.27, alpha: 1)])!.draw(in: body, angle: 90)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    body.lineWidth = 3 * s
    body.stroke()

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(srgbRed: 0.95, green: 0.3, blue: 0.6, alpha: 0.7)
    glow.shadowBlurRadius = 70 * s
    glow.set()
    let bar = NSBezierPath(roundedRect: r(170, 440, 684, 144), xRadius: 40 * s, yRadius: 40 * s)
    NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.45, blue: 0.55, alpha: 1),
                        NSColor(srgbRed: 0.85, green: 0.3, blue: 0.75, alpha: 1),
                        NSColor(srgbRed: 0.35, green: 0.35, blue: 1.0, alpha: 1)])!.draw(in: bar, angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    bar.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
        .draw(in: r(170, 512, 684, 72), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.45).setStroke()
    bar.lineWidth = 3 * s
    bar.stroke()

    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(ovalIn: r(204, 474, 76, 76)).fill()
    for i in 0..<3 {
        let tile = NSBezierPath(roundedRect: r(318 + CGFloat(i) * 112, 474, 92, 76), xRadius: 18 * s, yRadius: 18 * s)
        NSColor.black.withAlphaComponent(0.28).setFill()
        tile.fill()
        NSColor.white.withAlphaComponent(0.5).setStroke()
        tile.lineWidth = 2.5 * s
        tile.stroke()
    }
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: r(670, 498, 150, 28), xRadius: 14 * s, yRadius: 14 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try! draw(size: 1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(".build/AppIcon-preview.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
