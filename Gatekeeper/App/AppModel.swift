import AppKit
import Combine
import SafariServices
import ServiceManagement
import os

/// Everything the menu-bar popup and the settings window show, and the one place that changes it.
///
/// The Mac app has no rules and no exam mode of its own (docs/contract.md; Maxime's decision of 2026-10-17,
/// "Ask to connect"). It shows what the browser's engine decided and enforces exam mode on the Mac while the
/// engine says it is on. With no browser connected it asks to connect; an exam mode the browser started keeps
/// running here until its end, because that is the engine's decision, not the Mac's.
@MainActor
final class AppModel: ObservableObject {
    /// The last snapshot the followed browser sent (contract version 1); nil until it has sent one.
    @Published private(set) var snapshot: Snapshot?
    /// The browser the Mac follows (linked.json): the first to connect, or the one picked in Settings.
    @Published private(set) var linkedBrowser: String?
    /// Every browser that has sent a snapshot, newest first, for Settings.
    @Published private(set) var seenBrowsers: [String] = []
    /// Exam mode as the followed browser last said, kept until its end across relaunches (QA round 2, H3).
    @Published private(set) var heldExam: Follow.HeldExam? {
        didSet { save(heldExam, Keys.heldExam) }
    }
    /// The browser answered in the last two minutes.
    @Published private(set) var connected = false
    /// The clock the screens show, moved once a minute so the menu bar is not redrawn every two seconds.
    /// Exam mode reads the real time (Date()), so it starts and ends to the second.
    @Published private(set) var now = Date()

    // The browser running the extension, from the snapshot or found in the browsers' preferences.
    @Published private(set) var extensionBrowser: String?
    @Published private(set) var extensionID: String?

    /// A start of exam mode asked for on the Mac and not yet confirmed by the browser. The Mac hides apps at
    /// once, since a tightening is harmless; the popup shows it as on once a snapshot confirms it.
    @Published private(set) var pendingStart: PendingStart?

    struct PendingStart: Equatable {
        var until: Date
        var goal: String
        var asked: Date
        var queued: Date
    }

    @Published var examApps: [ExamApp] { didSet { save(examApps, Keys.examApps); applyGuardSettings() } }
    @Published var browserAction: ExamAction {
        didSet { defaults.set(browserAction.rawValue, forKey: Keys.browserAction); applyGuardSettings() }
    }

    /// Light by default; Maxime: "i prefer white honestly but i guess people differ, black is just too gloomy".
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance); appearance.apply() }
    }

    @Published private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginItemNeedsApproval = SMAppService.mainApp.status == .requiresApproval

    private let defaults = UserDefaults.standard
    private let guardian = ExamGuard()
    private let notice = KeptAwayNotice()
    private var timer: Timer?
    private var snapshotDate: Date?
    /// When the followed browser last sent a snapshot the Mac could read.
    var lastHeard: Date? { snapshotDate }
    private let log = Logger(subsystem: "com.gatekeeper.mac", category: "follow")

    private enum Keys {
        static let examApps = "examApps"
        static let browserAction = "browserAction"
        static let firstRunDone = "firstRunDone"
        static let appearance = "appearance"
        static let oldExamUntil = "examUntil" // the Mac's own exam mode, before 2026-10-17; removed at launch
        static let heldExam = "heldExam"
    }

    init() {
        examApps = Self.load([ExamApp].self, Keys.examApps) ?? ExamApp.defaults
        browserAction = ExamAction(rawValue: defaults.string(forKey: Keys.browserAction) ?? "") ?? .hide
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .light
        appearance.apply()
        defaults.removeObject(forKey: Keys.oldExamUntil)
        heldExam = Self.load(Follow.HeldExam.self, Keys.heldExam)
        try? FileManager.default.removeItem(at: NativeHost.oldTodayFile)

        if let found = Browsers.findExtension() {
            extensionBrowser = found.bundleID
            extensionID = found.extensionID
        }
        HostInstaller.install(extraIDs: [extensionID].compactMap { $0 })
        guardian.onKeptAway = { [weak self] app in
            guard let self, let until = self.examUntil else { return }
            self.notice.show(app: app, until: until)
        }
        #if DEBUG
        // Debug builds only: `open Gatekeeper.app --args -showTestNotice` shows one notice, to check it without
        // making another app come forward.
        if CommandLine.arguments.contains("-showTestNotice") {
            notice.show(app: "Mail", until: Date().addingTimeInterval(3600))
        }
        #endif
        logSafariState()
        applyGuardSettings()
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Writes to the log what Safari says about the Safari version of the extension, for finding out why it does
    /// not show in Safari's settings: `log show --predicate 'subsystem == "com.gatekeeper.mac"'`.
    private func logSafariState() {
        let log = self.log
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Browsers.safariExtensionID) { state, error in
            if let state {
                log.notice("safari extension found, \(state.isEnabled ? "on" : "off", privacy: .public)")
            } else {
                log.notice("safari extension not known to Safari: \(error.map { String(describing: $0) } ?? "no answer", privacy: .public)")
            }
        }
    }

    // MARK: First run

    /// True once: the first launch registers the login item and shows the settings window.
    func takeFirstRun() -> Bool {
        guard !defaults.bool(forKey: Keys.firstRunDone) else { return false }
        defaults.set(true, forKey: Keys.firstRunDone)
        setOpensAtLogin(true)
        return true
    }

    // MARK: The clock

    private func update() {
        let t = Date()
        if Int(t.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) { now = t }
        reloadSnapshot()
        let isConnected = Follow.connected(lastMessage: snapshotDate, now: t)
        if isConnected != connected {
            connected = isConnected
            log.notice("browser \(isConnected ? "connected" : "not connected", privacy: .public)")
        }
        followPendingStart(t)
        if examOn != guardian.active {
            log.notice("exam mode \(self.examOn ? "on till \(self.examUntil!.formatted())" : "off", privacy: .public)")
        }
        guardian.setActive(examOn)
        guardian.sweep()
    }

    /// Reads the followed browser's snapshot when its file changed. Only a snapshot the Mac can read, and no older
    /// than the last one, counts; a file it cannot read does not count as the browser speaking (QA round 2, H2).
    private func reloadSnapshot() {
        let linked = NativeHost.linked()
        if linked != linkedBrowser {
            linkedBrowser = linked
            snapshot = nil
            snapshotDate = nil
            if let b = linked, Browsers.known[b] != nil { extensionBrowser = b }
            applyGuardSettings()
        }
        let seen = NativeHost.seenBrowsers().map(\.key)
        if seen != seenBrowsers { seenBrowsers = seen }
        guard let key = linked else { return }
        let url = NativeHost.snapshotFile(key)
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              modified != snapshotDate,
              let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data), s.v == 1,
              s.at >= (snapshot?.at ?? 0)
        else { return }
        snapshotDate = modified
        snapshot = s
        let held = Follow.hold(heldExam, seeing: s, from: key)
        if held != heldExam { heldExam = held }
        if let b = s.browser, Browsers.known[b] != nil { extensionBrowser = b }
        if let id = s.extensionId { extensionID = id }
        applyGuardSettings()
    }

    /// Settings: follow another browser that has connected. Exam mode the Mac holds keeps running to its end.
    func follow(_ key: String) {
        NativeHost.setLinked(key)
        update()
    }

    private func applyGuardSettings() {
        guardian.apps = examApps
        guardian.browserAction = browserAction
        guardian.extensionBrowser = extensionBrowser
        guardian.sweep()
    }

    // MARK: Today

    /// The day the snapshot describes has ended and the browser has not sent the new one. The Mac does not
    /// reopen anything on its own clock (contract; QA finding H2).
    var isStale: Bool { snapshot.map { now >= $0.reopens } ?? false }

    var rings: [Ring] { guard let s = snapshot, !isStale else { return [] }; return Ring.rings(from: s) }

    var goal: String? {
        guard let s = snapshot else { return nil }
        let g = (confirmedExamUntil != nil ? s.exam?.goal : nil) ?? s.goal
        return g?.isEmpty == false ? g : nil
    }

    var canOpenExtension: Bool { extensionBrowser != nil && (extensionID != nil || snapshot?.base != nil) }

    var browserName: String {
        switch extensionBrowser {
        case "com.brave.Browser": return "Brave"
        case "com.google.Chrome": return "Chrome"
        case "com.apple.Safari": return "Safari"
        case let b?: return Browsers.name(b)
        case nil: return "your browser"
        }
    }

    // The pages the extension names in its snapshot; without one, the rules page, which every version has.
    private var rulesPage: String { snapshot?.pages?.rules ?? "pages/rules.html" }

    /// The one chat. In a full tab it needs ?from=rules, or it takes the toolbar popup's narrow layout.
    func openTalk() {
        let page = snapshot?.pages?.talk ?? "pages/talk.html"
        openPage(page.contains("?") ? page : page + "?from=rules")
    }

    func openRules() { openPage(rulesPage) }
    func openWeek() { openPage(snapshot?.pages?.week ?? rulesPage) }

    private func openPage(_ page: String) {
        guard let browser = extensionBrowser, let id = extensionID ?? snapshot?.base else { return }
        Browsers.open(page: page, extensionID: id, base: snapshot?.base, in: browser)
    }

    // MARK: Exam mode

    /// Exam mode as the browser's engine last said, even if the browser has since closed: it runs to its end.
    var confirmedExamUntil: Date? { Follow.confirmedExam(heldExam, now: Date()) }

    /// What the Mac enforces: the engine's exam mode, or a start the browser is confirming.
    var examUntil: Date? { Follow.enforcedExam(heldExam, pendingUntil: pendingStart?.until, now: Date()) }

    var examOn: Bool { examUntil != nil }

    /// Starting or extending exam mode is a tightening: a request to the browser's engine, enforced here at once.
    /// Only while the browser is connected; without it the Mac has no exam mode of its own.
    func startExam(until: Date, goal: String) {
        guard connected, until > Date() else { return }
        let t = Date()
        pendingStart = PendingStart(until: until, goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
                                    asked: t, queued: t)
        queueExamStart()
        update()
    }

    /// Ending early is a loosening, so it is never done on the Mac: this opens the browser's chat, where the
    /// agent decides (Maxime's decision of 2026-10-17).
    func endExamEarly() { openTalk() }

    // MARK: Requests to the extension (docs/contract.md)

    private func queueExamStart() {
        guard let p = pendingStart else { return }
        Requests.removeAll(ofType: "exam.start")
        var request: [String: Any] = ["type": "exam.start", "until": (p.until.timeIntervalSince1970 * 1000).rounded()]
        if !p.goal.isEmpty { request["goal"] = p.goal }
        Requests.queue(request)
    }

    private func followPendingStart(_ t: Date) {
        guard let p = pendingStart else { return }
        switch Follow.pendingStep(until: p.until, asked: p.asked, queued: p.queued,
                                  stillQueued: Requests.isQueued(type: "exam.start"),
                                  snapshot: snapshot, connected: connected, now: t) {
        case .confirmed:
            pendingStart = nil
        case .drop:
            pendingStart = nil
            Requests.removeAll(ofType: "exam.start")
        case .resend:
            pendingStart?.queued = t
            queueExamStart()
        case .wait:
            break
        }
    }

    /// While exam mode is on an app can be added to the list but not taken off it, or changed from quit to hide.
    func canRemove(_ app: ExamApp) -> Bool { !examOn }

    func add(appAt url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              !examApps.contains(where: { $0.bundleID == id }),
              id != extensionBrowser, id != NativeHost.appBundleID else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        examApps.append(ExamApp(bundleID: id, name: name, action: .hide))
    }

    func remove(_ app: ExamApp) {
        guard canRemove(app) else { return }
        examApps.removeAll { $0.bundleID == app.bundleID }
    }

    func setAction(_ action: ExamAction, for app: ExamApp) {
        guard let i = examApps.firstIndex(of: app) else { return }
        if examOn && action == .hide && app.action == .quit { return }
        examApps[i].action = action
    }

    func setBrowserAction(_ action: ExamAction) {
        if examOn && action == .hide && browserAction == .quit { return }
        browserAction = action
    }

    // MARK: Open at login

    func setOpensAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Gatekeeper: login item: \(error.localizedDescription)")
        }
        refreshLoginItem()
    }

    func refreshLoginItem() {
        opensAtLogin = SMAppService.mainApp.status == .enabled
        loginItemNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    // MARK: Storage

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The Appearance setting: the popup and the settings window in light, in dark, or as the Mac is set.
enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "Match Mac"
        }
    }

    @MainActor func apply() {
        switch self {
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp?.appearance = nil
        }
    }
}
