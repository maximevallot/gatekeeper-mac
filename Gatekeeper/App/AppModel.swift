import AppKit
import Combine
import SafariServices
import ServiceManagement
import os

/// Everything the menu-bar popup and the settings window show, and the one place that changes it.
///
/// Gatekeeper 0.3: one Gatekeeper per person. The account on the relay is the brain; the Mac app is a device in it,
/// like each browser (~/brain/outputs/html/2026-10-17-gatekeeper-one-per-person.html, step 5). It joins with the
/// 6-digit code another device shows, syncs about every 30 seconds, shows the account's Today and enforces its exam
/// mode on this Mac. It has no rules of its own and never loosens anything: its only request is to start exam mode.
@MainActor
final class AppModel: ObservableObject {
    static let syncEvery: TimeInterval = 30

    /// This Mac's place in the account; nil until it has joined with a code.
    @Published private(set) var membership: AccountMembership?
    /// The account's Today, from the last sync; nil until the first.
    @Published private(set) var snapshot: Snapshot?
    /// Exam mode as the account last said, kept until its end across relaunches and while offline (QA round 2, H3).
    @Published private(set) var heldExam: Follow.HeldExam? {
        didSet { save(heldExam, Keys.heldExam) }
    }
    /// The account answered in the last two minutes.
    @Published private(set) var connected = false
    /// Why the last join or sync failed, in words for the popup; nil when it worked.
    @Published private(set) var problem: String?
    @Published private(set) var joining = false
    /// The clock the screens show, moved once a minute so the menu bar is not redrawn every two seconds.
    /// Exam mode reads the real time (Date()), so it starts and ends to the second.
    @Published private(set) var now = Date()

    // The browser running the extension, found in the browsers' preferences, for opening its pages.
    @Published private(set) var extensionBrowser: String?
    @Published private(set) var extensionID: String?

    /// A start of exam mode asked for on the Mac and not yet confirmed by the account. The Mac hides apps at once,
    /// since a tightening is harmless; the popup shows it as on once a sync confirms it.
    @Published private(set) var pendingStart: PendingStart?

    struct PendingStart: Equatable {
        var id: String
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
    /// When the account last answered a sync.
    private(set) var lastSynced: Date?
    var lastHeard: Date? { lastSynced }
    private var syncing = false
    /// Requests waiting for the account to take them (only exam.start), sent with every sync until taken.
    private var outbox: [[String: Any]] = []
    /// The version of the account's copy the Mac last got; sent as `have`.
    private var copyVersion: Int?
    private let log = Logger(subsystem: "com.gatekeeper.mac", category: "account")

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
        membership = AccountStore.load()
        NativeHost.removeOldFiles()

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
        Task { await syncNow() }
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
        let isConnected = membership != nil && Follow.connected(lastMessage: lastSynced, now: t)
        if isConnected != connected {
            connected = isConnected
            log.notice("account \(isConnected ? "reachable" : "not reachable", privacy: .public)")
        }
        followPendingStart(t)
        if examOn != guardian.active {
            log.notice("exam mode \(self.examOn ? "on till \(self.examUntil!.formatted())" : "off", privacy: .public)")
        }
        guardian.setActive(examOn)
        guardian.sweep()
        if membership == nil, !joining, let code = NativeHost.takePairCode() {
            // A browser of the same account handed over a fresh code through native messaging.
            Task { await join(code: code) }
        }
        if let last = lastSynced, t.timeIntervalSince(last) < Self.syncEvery { return }
        Task { await syncNow() }
    }

    private func applyGuardSettings() {
        guardian.apps = examApps
        guardian.browserAction = browserAction
        guardian.extensionBrowser = extensionBrowser
        guardian.sweep()
    }

    // MARK: The account

    /// Joins the account with the 6-digit code another device shows under Settings › Add a device.
    func join(code: String) async {
        guard membership == nil, !joining else { return }
        joining = true
        defer { joining = false }
        do {
            let joined = try await AccountClient(relay: AccountClient.defaultRelay).join(code: code)
            try AccountStore.save(joined.membership)
            membership = joined.membership
            problem = nil
            lastSynced = Date()
            if let today = joined.today { accept(today) }
            log.notice("joined the account as device \(joined.membership.deviceId, privacy: .public)")
            update()
            await syncNow()
        } catch let failure as AccountClient.Failure {
            problem = Self.words(for: failure)
        } catch {
            problem = "Couldn't save this Mac's place in your Gatekeeper."
        }
    }

    /// One sync: send the outbox, take the account's Today. Every 30 seconds, and at once after a request.
    func syncNow() async {
        guard let m = membership, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let sent = outbox
            let synced = try await AccountClient(relay: URL(string: m.relay) ?? AccountClient.defaultRelay)
                .sync(m, have: copyVersion, requests: sent)
            lastSynced = Date()
            problem = nil
            if let v = synced.version { copyVersion = v }
            handle(results: synced.results)
            if let today = synced.today {
                accept(today)
            } else if !synced.unchanged {
                // No Today came back (an account without it): hold exam mode from the copy at least.
                acceptExam(synced.examFromCopy, at: AccountClient.millis(Date()))
            }
            update()
        } catch AccountClient.Failure.removed {
            // Removed from another device, or the account was deleted: carry on with what the Mac knows (exam mode
            // held to its end) and ask for a code again.
            AccountStore.clear()
            membership = nil
            snapshot = nil
            outbox.removeAll()
            problem = "This Mac was removed from your Gatekeeper. Join again with a code."
            update()
        } catch let failure as AccountClient.Failure {
            problem = Self.words(for: failure)
        } catch {
            problem = "Something went wrong talking to your Gatekeeper."
        }
    }

    /// An answered request is done. A refused exam start ends the wait at once and says why.
    private func handle(results: [String: [String: Any]]) {
        outbox.removeAll { ($0["id"] as? String).map { results[$0] != nil } ?? false }
        guard let p = pendingStart, let r = results[p.id] else { return }
        if let refused = r["refused"] as? String {
            pendingStart = nil
            problem = refused == "mac_cannot_loosen"
                ? "Your Gatekeeper refused that change from this Mac."
                : "Your Gatekeeper didn't start exam mode (\(refused))."
        }
    }

    /// Exam mode read from the account's copy, when no Today came with it.
    private func acceptExam(_ exam: Snapshot.Exam?, at: Double) {
        let s = Snapshot(v: 1, at: at, browser: nil, extensionId: nil, pages: nil, base: nil, goal: snapshot?.goal,
                         reopensAt: snapshot?.reopensAt ?? 0, waiting: nil, kinds: snapshot?.kinds ?? [],
                         sites: snapshot?.sites, exam: exam, watch: nil)
        let held = Follow.hold(heldExam, seeing: s)
        if held != heldExam { heldExam = held }
    }

    /// Only a snapshot no older than the last counts; exam mode is held from it (QA round 2, H2, H3).
    private func accept(_ s: Snapshot) {
        guard s.v == 1, s.at >= (snapshot?.at ?? 0) else { return }
        snapshot = s
        let held = Follow.hold(heldExam, seeing: s)
        if held != heldExam { heldExam = held }
    }

    /// Leave this account, on this Mac. Leaving loosens nothing: exam mode the Mac holds runs to its end.
    func leaveAccount() async {
        guard let m = membership else { return }
        await AccountClient(relay: URL(string: m.relay) ?? AccountClient.defaultRelay).leave(m)
        AccountStore.clear()
        membership = nil
        snapshot = nil
        outbox.removeAll()
        lastSynced = nil
        update()
    }

    static func words(for failure: AccountClient.Failure) -> String {
        switch failure {
        case let .badCode(reason):
            switch reason {
            case "too_many_codes", "daily_limit": return "Too many tries for now. Wait a little, then get a new code."
            default: return "That code didn't work: it may be wrong, used or older than 10 minutes. Get a new one under Settings › Add a device."
            }
        case .removed: return "This Mac was removed from your Gatekeeper. Join again with a code."
        case .unreachable: return "Can't reach your Gatekeeper. Check the internet connection."
        case let .server(status, _): return "Your Gatekeeper didn't answer properly (\(status)). It will try again."
        case .badReply: return "Your Gatekeeper sent something this Mac can't read. Update Gatekeeper for Mac."
        }
    }

    // MARK: Today

    /// The day the snapshot describes has ended and the account has not sent the new one. The Mac does not
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

    // The pages the extension names; without them, the rules page, which every version has.
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

    /// Exam mode as the account last said, even offline: it runs to its end.
    var confirmedExamUntil: Date? { Follow.confirmedExam(heldExam, now: Date()) }

    /// What the Mac enforces: the account's exam mode, or a start the account is confirming.
    var examUntil: Date? { Follow.enforcedExam(heldExam, pendingUntil: pendingStart?.until, now: Date()) }

    var examOn: Bool { examUntil != nil }

    /// Starting or extending exam mode is a tightening: a request to the account, enforced here at once. Only while
    /// the account answers; without it the Mac has no exam mode of its own.
    func startExam(until: Date, goal: String) {
        guard connected, until > Date() else { return }
        let t = Date()
        pendingStart = PendingStart(id: UUID().uuidString, until: until,
                                    goal: goal.trimmingCharacters(in: .whitespacesAndNewlines), asked: t, queued: t)
        queueExamStart()
        update()
        Task { await syncNow() }
    }

    /// Ending early is a loosening, so it is never done on the Mac: this opens the browser's chat, where the
    /// agent decides (Maxime's decision of 2026-10-17).
    func endExamEarly() { openTalk() }

    private func queueExamStart() {
        guard let p = pendingStart else { return }
        outbox.removeAll { $0["type"] as? String == "startExam" }
        var request: [String: Any] = ["id": p.id, "type": "startExam", "source": "mac", "until": AccountClient.millis(p.until)]
        if !p.goal.isEmpty { request["goal"] = p.goal }
        outbox.append(request)
    }

    private func followPendingStart(_ t: Date) {
        guard let p = pendingStart else { return }
        let stillQueued = outbox.contains { $0["type"] as? String == "startExam" }
        switch Follow.pendingStep(until: p.until, asked: p.asked, queued: p.queued, stillQueued: stillQueued,
                                  snapshot: snapshot, connected: connected, now: t) {
        case .confirmed:
            pendingStart = nil
        case .drop:
            pendingStart = nil
            outbox.removeAll { $0["type"] as? String == "startExam" }
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
