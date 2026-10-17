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

    @Published private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var loginItemNeedsApproval = SMAppService.mainApp.status == .requiresApproval

    private let defaults = UserDefaults.standard
    private let guardian = ExamGuard()
    private var timer: Timer?
    private var snapshotDate: Date?

    private enum Keys {
        static let examUntil = "examUntil"
        static let examApps = "examApps"
        static let browserAction = "browserAction"
        static let firstRunDone = "firstRunDone"
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Gatekeeper", isDirectory: true)
    }

    static var todayFile: URL { folder.appendingPathComponent("today.json") }

    init() {
        examApps = Self.load([ExamApp].self, Keys.examApps) ?? ExamApp.defaults
        browserAction = ExamAction(rawValue: defaults.string(forKey: Keys.browserAction) ?? "") ?? .hide
        if let t = defaults.object(forKey: Keys.examUntil) as? Double { localExamUntil = Date(timeIntervalSince1970: t) }

        if let found = Browsers.findExtension() {
            extensionBrowser = found.bundleID
            extensionID = found.extensionID
        }
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
        guardian.setActive(examOn)
        guardian.sweep()
    }

    private func reloadSnapshot() {
        let url = Self.todayFile
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
        if let b = s.browser { extensionBrowser = b }
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

    func openRules() { openPage(snapshot.pages?.rules ?? "pages/rules.html") }

    /// The extension has no week page yet; until it does, this opens the rules page.
    func openWeek() { openPage(snapshot.pages?.week ?? snapshot.pages?.rules ?? "pages/rules.html") }

    private func openPage(_ page: String) {
        guard let browser = extensionBrowser, let id = extensionID else { return }
        Browsers.open(page: page, extensionID: id, in: browser)
    }

    // MARK: Exam mode

    /// The later of the Mac's exam mode and the extension's: whichever ends last is in force.
    var examUntil: Date? {
        let fromExtension = snapshot.exam.map { Date(timeIntervalSince1970: $0.until / 1000) }
        let latest = [localExamUntil, isSample ? nil : fromExtension].compactMap { $0 }.max()
        guard let until = latest, until > now else { return nil }
        return until
    }

    var examOn: Bool { examUntil != nil }

    /// Starting or extending exam mode is a tightening: it applies at once.
    func startExam(until: Date) {
        guard until > Date() else { return }
        localExamUntil = max(until, localExamUntil ?? until)
        update()
    }

    /// Ending early takes the sentence, typed. Returns false if it does not match.
    func endExam(sentence: String) -> Bool {
        let typed = sentence.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard typed.caseInsensitiveCompare(Self.endSentence) == .orderedSame else { return false }
        localExamUntil = nil
        update()
        return true
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
