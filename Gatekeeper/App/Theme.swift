import SwiftUI
import AppKit

// The colors of the design canvas (~/brain/outputs/gatekeeper-simplified-design/Main.dc.html for light,
// TodayDark.dc.html for dark), the same tokens the extension uses. Light is the default; dark is deep slate,
// not black. Which one shows is the Appearance setting (AppModel.appearance).
enum Theme {
    static let accent = dynamic(light: 0x3B5BDB, dark: 0x7D96FF)
    /// Behind the main button's text and icon.
    static let accentFill = dynamic(light: 0x3B5BDB, dark: 0x7D96FF)
    /// Text and icons on accentFill.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x10131F)
    static let link = dynamic(light: 0x3B5BDB, dark: 0x9FB2FF)
    static let accentText = dynamic(light: 0x2B44A8, dark: 0xAFC0FF)
    static let accentSoft = dynamic(light: 0xEEF1FD, dark: 0x26304F)
    static let closed = dynamic(light: 0xB42318, dark: 0xFF8A7A)
    static let closedSoft = dynamic(light: 0xF3C6C1, dark: 0x5A2F2B)
    /// line: ring tracks and dividers.
    static let track = dynamic(light: 0xE3E6EE, dark: 0x2E333D)
    /// ground: the goal card and other inset blocks.
    static let card = dynamic(light: 0xF6F7FB, dark: 0x171A20)
    /// surface: the popup and the settings window.
    static let background = dynamic(light: 0xFFFFFF, dark: 0x1F232B)
    static let text = dynamic(light: 0x161A23, dark: 0xECEFF4)
    static let muted = dynamic(light: 0x5B6270, dark: 0xA3AAB7)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        })
    }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The gate mark from the extension's icon: an arch with a crossbar. Drawn, so it is sharp at any size.
enum GateMark {
    static func path(in rect: CGRect, lineWidth: CGFloat) -> NSBezierPath {
        let inset = lineWidth / 2
        let left = rect.minX + rect.width * 0.22 + inset
        let right = rect.maxX - rect.width * 0.22 - inset
        let bottom = rect.minY + rect.height * 0.16 + inset
        let top = rect.maxY - rect.height * 0.16 - inset
        let radius = (right - left) / 2
        let p = NSBezierPath()
        p.move(to: CGPoint(x: left, y: bottom))
        p.line(to: CGPoint(x: left, y: top - radius))
        p.appendArc(withCenter: CGPoint(x: left + radius, y: top - radius), radius: radius,
                    startAngle: 180, endAngle: 0, clockwise: true)
        p.line(to: CGPoint(x: right, y: bottom))
        let bar = bottom + (top - bottom) * 0.48
        p.move(to: CGPoint(x: left, y: bar))
        p.line(to: CGPoint(x: right, y: bar))
        p.lineWidth = lineWidth
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        return p
    }

    /// The menu-bar image: a template, so macOS colors it for light and dark menu bars.
    static func menuBarImage(locked: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            path(in: rect, lineWidth: 2).stroke()
            if locked {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: CGRect(x: rect.midX - 2.5, y: rect.minY + 2.2, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = locked ? "Gatekeeper, exam mode" : "Gatekeeper"
        return image
    }
}
