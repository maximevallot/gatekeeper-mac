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
/// running the extension get the same. When exam mode ends, the apps it hid come back (not to the front).
/// Hiding and quitting other apps needs no macOS permission.
@MainActor
final class ExamGuard {
    var apps: [ExamApp] = []
    var browserAction: ExamAction = .hide
    /// The browser running the extension. Unknown: every Chromium browser is spared, since any could be it.
    var extensionBrowser: String?

    /// Called when the user tries to open or bring forward an app that exam mode keeps away.
    var onKeptAway: ((String) -> Void)?

    private(set) var active = false
    private var observers: [NSObjectProtocol] = []
    private var hiddenByExam: Set<pid_t> = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.handle(app, byUser: true) }
            })
        }
    }

    func setActive(_ on: Bool) {
        let wasActive = active
        active = on
        if on { sweep() } else if wasActive { restore() }
    }

    /// Brings back what exam mode hid, without bringing anything to the front.
    private func restore() {
        for pid in hiddenByExam { NSRunningApplication(processIdentifier: pid)?.unhide() }
        hiddenByExam.removeAll()
    }

    /// Acts on every running app. Called when exam mode starts and every few seconds while it is on, which
    /// catches a window that appears without its app coming to the front.
    func sweep() {
        guard active else { return }
        for app in NSWorkspace.shared.runningApplications { handle(app, byUser: false) }
    }

    func action(for bundleID: String) -> ExamAction? {
        if let app = apps.first(where: { $0.bundleID == bundleID }) { return app.action }
        guard Browsers.known[bundleID] != nil else { return nil }
        if let mine = extensionBrowser {
            return bundleID == mine ? nil : browserAction
        }
        return Browsers.chromium.contains(where: { $0.bundleID == bundleID }) ? nil : browserAction
    }

    private func handle(_ app: NSRunningApplication, byUser: Bool) {
        guard active, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let id = app.bundleIdentifier, let action = action(for: id) else { return }
        // An app exam mode already hid that is visible again: someone brought it back, so it counts as a try.
        let cameBack = hiddenByExam.contains(app.processIdentifier) && !app.isHidden
        switch action {
        case .hide:
            guard !app.isHidden || byUser else { return }
            app.hide()
            hiddenByExam.insert(app.processIdentifier)
        case .quit:
            guard !app.isTerminated else { return }
            app.terminate()
        }
        if byUser || cameBack { onKeptAway?(app.localizedName ?? id) }
    }
}
