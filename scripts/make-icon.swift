// Draws the app icon (the gate mark in white on the accent) into Gatekeeper/Assets.xcassets/AppIcon.appiconset.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let out = URL(fileURLWithPath: "Gatekeeper/Assets.xcassets/AppIcon.appiconset")
let accent = NSColor(srgbRed: 0x3B / 255, green: 0x5B / 255, blue: 0xDB / 255, alpha: 1)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: the rounded square fills 824 of 1024, centered.
    let inset = s * 100 / 1024
    let square = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    accent.setFill()
    NSBezierPath(roundedRect: square, xRadius: square.width * 0.225, yRadius: square.width * 0.225).fill()
    let w = square.width * 0.11
    let r = square.insetBy(dx: square.width * 0.06, dy: square.width * 0.06)
    let left = r.minX + r.width * 0.22 + w / 2, right = r.maxX - r.width * 0.22 - w / 2
    let bottom = r.minY + r.height * 0.16 + w / 2, top = r.maxY - r.height * 0.16 - w / 2
    let radius = (right - left) / 2
    let p = NSBezierPath()
    p.move(to: CGPoint(x: left, y: bottom))
    p.line(to: CGPoint(x: left, y: top - radius))
    p.appendArc(withCenter: CGPoint(x: left + radius, y: top - radius), radius: radius, startAngle: 180, endAngle: 0, clockwise: true)
    p.line(to: CGPoint(x: right, y: bottom))
    let bar = bottom + (top - bottom) * 0.48
    p.move(to: CGPoint(x: left, y: bar)); p.line(to: CGPoint(x: right, y: bar))
    p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round
    NSColor.white.setStroke(); p.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! draw(size * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let json = try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
                                       options: [.prettyPrinted, .sortedKeys])
try! json.write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons")
