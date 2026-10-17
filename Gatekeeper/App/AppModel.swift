import AppKit
import Combine
import ServiceManagement

/// Everything the menu-bar popup and the settings window show, and the one place that changes it.
@MainActor
final class AppModel: ObservableObject {
    static let endSentence = "I am choosing to stop preparing for my exam"

    // Today, from the extension (docs/contract.md), or the design's sample until the bridge exists.
    @Published private(set) var snapshot: Snapshot = .sample()
    @Published private(set) var isSample = true
    @Published private(set) var now = Date()

    // The browser running the extension, from the snapshot or found in the browsers' preferences.
    @Published private(set) var extensionBrowser: String?
    @Published private(set) var extensionID: String?

    // Exam mode started on this Mac. The extension's exam mode, once it has one, comes in the snapshot.
    @Published private(set) var localExamUntil: Date? {
        didSet { defaults.set(localExamUntil?.timeIntervalSince1970, forKey: Keys.examUntil) }
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
    private var timer: Timer?
    private var snapshotDate: Date?
    /// The end (ms) of the exam mode last ended with the sentence. A snapshot's exam mode that ends no later is
    /// the same one, sent before the extension applied the end, and is ignored.
    private var endedUntil: Double {
        didSet { defaults.set(endedUntil, forKey: Keys.examEndedUntil) }
    }
    private var lastStartQueued: Date?

    private enum Keys {
        static let examUntil = "examUntil"
        static let examApps = "examApps"
        static let browserAction = "browserAction"
        static let firstRunDone = "firstRunDone"
        static let appearance = "appearance"
        static let examEndedUntil = "examEndedUntil"
    }

    init() {
        examApps = Self.load([ExamApp].self, Keys.examApps) ?? ExamApp.defaults
        browserAction = ExamAction(rawValue: defaults.string(forKey: Keys.browserAction) ?? "") ?? .hide
        endedUntil = defaults.double(forKey: Keys.examEndedUntil)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .light
        appearance.apply()
        if let t = defaults.object(forKey: Keys.examUntil) as? Double { localExamUntil = Date(timeIntervalSince1970: t) }

        if let found = Browsers.findExtension() {
            extensionBrowser = found.bundleID
            extensionID = found.extensionID
        }
        HostInstaller.install(extraIDs: [extensionID].compactMap { $0 })
        reloadSnapshot()
        applyGuardSettings()
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
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
        now = Date()
        reloadSnapshot()
        if let until = localExamUntil, until <= now { localExamUntil = nil }
        resendExamStartIfLost()
        guardian.setActive(examOn)
        guardian.sweep()
    }

    private func reloadSnapshot() {
        let url = NativeHost.todayFile
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else {
            if !isSample { isSample = true; snapshot = .sample() }
            return
        }
        guard modified != snapshotDate else { return }
        snapshotDate = modified
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Snapshot.self, from: data),
              s.v == 1 else { return }
        snapshot = s
        isSample = false
        if let b = s.browser, Browsers.known[b] != nil { extensionBrowser = b }
        if let id = s.extensionId { extensionID = id }
        applyGuardSettings()
    }

    private func applyGuardSettings() {
        guardian.apps = examApps
        guardian.browserAction = browserAction
        guardian.extensionBrowser = extensionBrowser
        guardian.sweep()
    }

    // MARK: Today

    var rings: [Ring] { Ring.rings(from: snapshot, now: now) }

    var goal: String? {
        let g = (examOn ? snapshot.exam?.goal : nil) ?? snapshot.goal
        return g?.isEmpty == false ? g : nil
    }

    var canOpenExtension: Bool { extensionBrowser != nil && extensionID != nil }

    // The pages the extension names in its snapshot; without one, the rules page, which every version has.
    private var rulesPage: String { snapshot.pages?.rules ?? "pages/rules.html" }
    func openTalk() { openPage(snapshot.pages?.talk ?? rulesPage) }
    func openRules() { openPage(rulesPage) }
    func openWeek() { openPage(snapshot.pages?.week ?? rulesPage) }

    private func openPage(_ page: String) {
        guard let browser = extensionBrowser, let id = extensionID else { return }
        Browsers.open(page: page, extensionID: id, in: browser)
    }

    // MARK: Exam mode

    /// The later of the Mac's exam mode and the extension's: whichever ends last is in force.
    var examUntil: Date? {
        let fromExtension = snapshot.exam.flatMap { $0.until > endedUntil ? Date(timeIntervalSince1970: $0.until / 1000) : nil }
        let latest = [localExamUntil, isSample ? nil : fromExtension].compactMap { $0 }.max()
        guard let until = latest, until > now else { return nil }
        return until
    }

    var examOn: Bool { examUntil != nil }

    /// Starting or extending exam mode is a tightening: it applies at once.
    func startExam(until: Date) {
        guard until > Date() else { return }
        localExamUntil = max(until, localExamUntil ?? until)
        queueExamStart()
        update()
    }

    /// Ending early takes the sentence, typed. Returns false if it does not match.
    func endExam(sentence: String) -> Bool {
        let typed = sentence.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard typed.caseInsensitiveCompare(Self.endSentence) == .orderedSame else { return false }
        if let until = examUntil { endedUntil = max(endedUntil, until.timeIntervalSince1970 * 1000) }
        localExamUntil = nil
        Requests.removeAll(ofType: "exam.start")
        Requests.queue(["type": "exam.end", "sentence": Self.endSentence])
        update()
        return true
    }

    // MARK: Requests to the extension (docs/contract.md)

    private func queueExamStart() {
        guard let until = localExamUntil else { return }
        Requests.removeAll(ofType: "exam.start")
        Requests.queue(["type": "exam.start", "until": (until.timeIntervalSince1970 * 1000).rounded()])
        lastStartQueued = Date()
    }

    /// The extension shows the Mac's exam mode in its next snapshot. If it has not two minutes after the request
    /// was handed over (the extension is talking to the bridge, the request file is gone), queue it again.
    private func resendExamStartIfLost() {
        guard let until = localExamUntil, !isSample else { return }
        let known = snapshot.exam.map { $0.until >= until.timeIntervalSince1970 * 1000 - 1000 } ?? false
        if known { return }
        if Requests.isQueued(type: "exam.start") { return }
        if let last = lastStartQueued, now.timeIntervalSince(last) < 120 { return }
        queueExamStart()
    }

    /// While exam mode is on an app can be added to the list but not taken off it, or changed from quit to hide.
    func canRemove(_ app: ExamApp) -> Bool { !examOn }

    func add(appAt url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              !examApps.contains(where: { $0.bundleID == id }) else { return }
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
