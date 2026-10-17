import AppKit

/// What exam mode does to an app on the list.
enum ExamAction: String, Codable, CaseIterable, Identifiable {
    case hide, quit
    var id: String { rawValue }
    var title: String { self == .hide ? "Hide" : "Quit" }
}

struct ExamApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var action: ExamAction
    var id: String { bundleID }

    static let defaults: [ExamApp] = [
        ExamApp(bundleID: "com.apple.mail", name: "Mail", action: .hide),
        ExamApp(bundleID: "com.microsoft.Outlook", name: "Microsoft Outlook", action: .hide),
        ExamApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", action: .hide),
        ExamApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", action: .hide),
        ExamApp(bundleID: "com.apple.MobileSMS", name: "Messages", action: .hide),
        ExamApp(bundleID: "com.hnc.Discord", name: "Discord", action: .hide),
    ]
}

/// The Mac's hands in exam mode. While it is on, an app on the list is hidden (or quit) when exam mode starts,
/// whenever it is launched or brought to the front, and at every check in between. Browsers other than the one
/// running the extension get the same. Hiding and quitting other apps needs no macOS permission.
@MainActor
final class ExamGuard {
    var apps: [ExamApp] = []
    var browserAction: ExamAction = .hide
    /// The browser running the extension. Unknown: every Chromium browser is spared, since any could be it.
    var extensionBrowser: String?

    private(set) var active = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.handle(app) }
            })
        }
    }

    func setActive(_ on: Bool) {
        active = on
        if on { sweep() }
    }

    /// Acts on every running app. Called when exam mode starts and every few seconds while it is on, which
    /// catches a window that appears without its app coming to the front.
    func sweep() {
        guard active else { return }
        for app in NSWorkspace.shared.runningApplications { handle(app) }
    }

    func action(for bundleID: String) -> ExamAction? {
        if let app = apps.first(where: { $0.bundleID == bundleID }) { return app.action }
        guard Browsers.known[bundleID] != nil else { return nil }
        if let mine = extensionBrowser {
            return bundleID == mine ? nil : browserAction
        }
        return Browsers.chromium.contains(where: { $0.bundleID == bundleID }) ? nil : browserAction
    }

    private func handle(_ app: NSRunningApplication) {
        guard active, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let id = app.bundleIdentifier, let action = action(for: id) else { return }
        switch action {
        case .hide:
            if !app.isHidden { app.hide() }
        case .quit:
            if !app.isTerminated { app.terminate() }
        }
    }
}
