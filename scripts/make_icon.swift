// Draws an original optical-disc app icon: swift tools/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(_ pixels: Int) throws -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    let inset = s * 0.09
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.34, blue: 0.62, alpha: 1), NSColor(red: 0.06, green: 0.14, blue: 0.30, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18), angle: -90)

    let c = NSPoint(x: s / 2, y: s / 2)
    func circle(_ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    let disc = circle(s * 0.33)
    NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(red: 0.74, green: 0.84, blue: 0.95, alpha: 1), NSColor(white: 0.92, alpha: 1)])!
        .draw(in: disc, angle: 40)
    NSColor(white: 1, alpha: 0.65).setStroke()
    for fraction in [0.27, 0.22, 0.17] {
        let ring = circle(s * CGFloat(fraction))
        ring.lineWidth = max(1, s * 0.004)
        ring.stroke()
    }
    NSColor(red: 0.16, green: 0.34, blue: 0.62, alpha: 1).setFill()
    circle(s * 0.095).fill()
    NSColor(red: 0.06, green: 0.14, blue: 0.30, alpha: 1).setFill()
    circle(s * 0.05).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    try render(points * scale).write(to: output.appendingPathComponent(name))
    images.append(["size": "\(points)x\(points)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
