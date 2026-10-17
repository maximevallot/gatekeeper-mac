import AppKit
import os

/// A short notice at the top of the screen when exam mode keeps an app away, so it does not just vanish:
/// "Slack waits till 18:00". It takes no clicks and fades after a few seconds. No notification permission needed.
/// Plain AppKit, shown on the next turn of the run loop, so it never runs inside a SwiftUI update.
@MainActor
final class KeptAwayNotice {
    private var panel: NSPanel?
    private var lastShown: [String: Date] = [:]
    private var hideWork: DispatchWorkItem?
    private let log = Logger(subsystem: "com.gatekeeper.mac", category: "exam")

    func show(app: String, until: Date) {
        let now = Date()
        if let last = lastShown[app], now.timeIntervalSince(last) < 20 { return }
        lastShown[app] = now
        log.notice("exam mode kept \(app, privacy: .public) away")
        let text = "\(app) waits till \(until.formatted(date: .omitted, time: .shortened))"
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.present(text) }
        }
    }

    private func present(_ text: String) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Theme.AppKit.text
        let lock = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) ?? NSImage())
        lock.symbolConfiguration = .init(pointSize: 12, weight: .bold)
        lock.contentTintColor = Theme.AppKit.accent
        let row = NSStackView(views: [lock, label])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        let size = row.fittingSize

        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.AppKit.surface.cgColor
        box.layer?.borderColor = Theme.AppKit.line.cgColor
        box.layer?.borderWidth = 1
        box.layer?.cornerRadius = size.height / 2
        row.frame = box.bounds
        box.addSubview(row)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = box
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 16))
        }
        p.orderFrontRegardless()
        panel = p
        log.notice("notice shown: \(text, privacy: .public)")

        let work = DispatchWorkItem { [weak p] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; p?.animator().alphaValue = 0 },
                                                 completionHandler: { p?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
