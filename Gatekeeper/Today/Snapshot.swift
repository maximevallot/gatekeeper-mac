import Foundation

/// What the extension tells the Mac about today, as docs/contract.md defines it (version 1): the engine's
/// todaySummary, plus the pages and exam mode. The bridge writes it to today.json; the app only reads it and works
/// nothing out from it. Times are milliseconds since 1970, as the extension's engine keeps them.
struct Snapshot: Codable, Equatable {
    struct Kind: Codable, Equatable, Identifiable {
        var kind: String
        var label: String
        var short: String?
        /// nil only for a site closed in exam mode alone ("examOnly"), open every other day.
        var minutes: Int?
        var left: Int?
        var status: String // "open", "spent" or "closed"
        var fraction: Double?
        /// Closed by exam mode rather than by its own budget.
        var exam: Bool?
        /// For a row of `sites`: the domain with its own limit.
        var site: String?
        var examOnly: Bool?
        var id: String { kind }
    }

    struct Pages: Codable, Equatable {
        var today: String?
        var rules: String?
        var talk: String?
        var week: String?
        var exam: String?
    }

    struct Exam: Codable, Equatable {
        var until: Double
        var goal: String?
    }

    /// A new install's first week: every kind counted, nothing blocked.
    struct Watch: Codable, Equatable {
        var day: Int?
        var of: Int?
        var until: Double?
    }

    var v: Int
    var at: Double
    var browser: String?
    var extensionId: String?
    var pages: Pages?
    /// The extension's own base address, `runtime.getURL("")`. Safari's is safari-web-extension://<uuid>/,
    /// which no ID gives; without it the Mac builds chrome-extension://<extensionId>/.
    var base: String?
    var goal: String?
    var reopensAt: Double
    var waiting: Bool?
    var kinds: [Kind]
    /// Sites with a daily limit of their own, after the kinds; same shape, kind "s:<domain>".
    var sites: [Kind]?
    var exam: Exam?
    var watch: Watch?

    var reopens: Date { Date(timeIntervalSince1970: reopensAt / 1000) }
}

// Reading is strict about the few fields the Mac cannot do without (v, at, reopensAt, kinds) and lenient about
// the rest: a row that cannot be read is skipped, not the whole day, and a field of the wrong type counts as
// missing (QA round 2, H2). Numbers may come as integers or decimals; exam.until may also be an ISO 8601 time.

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? { (try? decodeIfPresent(type, forKey: key)) ?? nil }

    /// An integer that may have been sent as a decimal (7.5 → 8).
    func lenientInt(_ key: Key) -> Int? {
        if let i = lenient(Int.self, key) { return i }
        return lenient(Double.self, key).map { Int($0.rounded()) }
    }

    /// Milliseconds since 1970, sent as a number or as an ISO 8601 time.
    func milliseconds(_ key: Key) throws -> Double {
        if let n = lenient(Double.self, key) { return n }
        let text = try decode(String.self, forKey: key)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        guard let date = f.date(from: text) ?? g.date(from: text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not a time: \(text)")
        }
        return date.timeIntervalSince1970 * 1000
    }
}

extension Snapshot {
    private enum Keys: String, CodingKey {
        case v, at, browser, extensionId, pages, base, goal, reopensAt, waiting, kinds, sites, exam, watch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        v = try c.decode(Int.self, forKey: .v)
        at = try c.milliseconds(.at)
        reopensAt = try c.milliseconds(.reopensAt)
        kinds = try c.decode([Lossy<Kind>].self, forKey: .kinds).compactMap(\.value)
        sites = c.lenient([Lossy<Kind>].self, .sites)?.compactMap(\.value)
        browser = c.lenient(String.self, .browser)
        extensionId = c.lenient(String.self, .extensionId)
        pages = c.lenient(Pages.self, .pages)
        base = c.lenient(String.self, .base)
        goal = c.lenient(String.self, .goal)
        waiting = c.lenient(Bool.self, .waiting)
        exam = c.lenient(Exam.self, .exam)
        watch = c.lenient(Watch.self, .watch)
    }
}

extension Snapshot.Kind {
    private enum Keys: String, CodingKey {
        case kind, label, short, minutes, left, status, fraction, exam, site, examOnly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kind = try c.decode(String.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        status = try c.decode(String.self, forKey: .status)
        short = c.lenient(String.self, .short)
        minutes = c.lenientInt(.minutes)
        left = c.lenientInt(.left)
        fraction = c.lenient(Double.self, .fraction)
        exam = c.lenient(Bool.self, .exam)
        site = c.lenient(String.self, .site)
        examOnly = c.lenient(Bool.self, .examOnly)
    }
}

extension Snapshot.Exam {
    private enum Keys: String, CodingKey { case until, goal }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        until = try c.milliseconds(.until)
        goal = c.lenient(String.self, .goal)
    }
}

/// One ring on the Today screen, exactly as the engine decided it.
struct Ring: Identifiable, Equatable {
    enum State: Equatable {
        case open(minutesLeft: Int, fraction: Double)
        /// A site closed only in exam mode: open today, no minutes counted.
        case examOnly
        case spent(reopens: Date)
        case closedAllDay
    }

    let id: String
    let name: String
    let state: State

    static func rings(from s: Snapshot) -> [Ring] {
        (s.kinds + (s.sites ?? [])).map { k in
            let name = k.short ?? k.label
            switch k.status {
            case "closed":
                if k.exam == true, let exam = s.exam {
                    return Ring(id: k.kind, name: name, state: .spent(reopens: Date(timeIntervalSince1970: exam.until / 1000)))
                }
                return Ring(id: k.kind, name: name, state: .closedAllDay)
            case "spent":
                return Ring(id: k.kind, name: name, state: .spent(reopens: s.reopens))
            default:
                guard let minutes = k.minutes, let left = k.left else {
                    return Ring(id: k.kind, name: name, state: .examOnly)
                }
                let fraction = k.fraction ?? (minutes > 0 ? Double(left) / Double(minutes) : 0)
                return Ring(id: k.kind, name: name, state: .open(minutesLeft: left, fraction: min(1, max(0, fraction))))
            }
        }
    }
}

enum Day {
    /// "18:00" today, "Wed 08:30" another day (QA round 2, M3).
    static func until(_ date: Date, now: Date = Date()) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(date, inSameDayAs: now) { return time }
        return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    /// The next moment the day turns over (4:00 by default), as the engine's nextDayStart.
    static func nextStart(after now: Date, hour: Int) -> Date {
        let cal = Calendar.current
        var d = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        if d <= now { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }
}

/// What the Mac follows, worked out from the browser's last word alone, so it can be tested without a screen.
enum Follow {
    /// How long after the browser's last message it still counts as connected. It calls every minute.
    static let connectedFor: TimeInterval = 120
    /// A start the browser has not confirmed after this long is dropped (it refused it, or never got it).
    static let pendingFor: TimeInterval = 600
    /// A start the browser took but does not show after this long is asked for again.
    static let resendAfter: TimeInterval = 120

    static func connected(lastMessage: Date?, now: Date) -> Bool {
        lastMessage.map { now.timeIntervalSince($0) < connectedFor } ?? false
    }

    /// Exam mode as the followed browser's engine last said. It is kept (and saved, so a relaunch keeps it) until
    /// its end, or until a newer snapshot from the same browser says exam mode is off; an older snapshot changes
    /// nothing (QA round 2, C2 and H3).
    struct HeldExam: Codable, Equatable {
        var until: Double // ms
        var seenAt: Double // the `at` of the snapshot that said so
        /// The browser whose snapshot said so (its key); nil for one saved before QA round 3.
        var source: String?
    }

    /// `source` is the browser the snapshot came from. While a held exam mode is running, a snapshot from another
    /// browser can only make it longer, never end or shorten it: switching Follows in Settings during exam mode must
    /// not end it (QA round 3, N1). Only a newer snapshot from the browser that started it, or its end, ends it.
    static func hold(_ held: HeldExam?, seeing s: Snapshot, from source: String? = nil, now: Date = Date()) -> HeldExam? {
        if let held, let started = held.source, started != source, held.until > now.timeIntervalSince1970 * 1000 {
            if let exam = s.exam, exam.until > held.until { return HeldExam(until: exam.until, seenAt: s.at, source: source) }
            return held
        }
        if let held, s.at < held.seenAt { return held }
        return s.exam.map { HeldExam(until: $0.until, seenAt: s.at, source: source) }
    }

    static func confirmedExam(_ held: HeldExam?, now: Date) -> Date? {
        guard let held else { return nil }
        let until = Date(timeIntervalSince1970: held.until / 1000)
        return until > now ? until : nil
    }

    /// What the Mac enforces: the engine's exam mode, or a start the browser is confirming.
    static func enforcedExam(_ held: HeldExam?, pendingUntil: Date?, now: Date) -> Date? {
        if let until = confirmedExam(held, now: now) { return until }
        if let p = pendingUntil, p > now { return p }
        return nil
    }

    enum PendingStep: Equatable { case wait, confirmed, drop, resend }

    /// What to do with a start of exam mode asked for on the Mac. Confirmed once a snapshot shows it (the engine
    /// holds it now). Dropped when the browser stops answering (the Mac has no exam mode of its own), after ten
    /// minutes unconfirmed, or at its end. Sent again if the browser took it and two minutes passed with no sign.
    static func pendingStep(until: Date, asked: Date, queued: Date, stillQueued: Bool,
                            snapshot: Snapshot?, connected: Bool, now: Date) -> PendingStep {
        // Any exam mode on counts: the engine may have cut the end to its 14-day maximum (QA round 2, M2).
        if let exam = snapshot?.exam, exam.until > now.timeIntervalSince1970 * 1000 { return .confirmed }
        if !connected || now.timeIntervalSince(asked) > pendingFor || until <= now { return .drop }
        if !stillQueued && now.timeIntervalSince(queued) > resendAfter { return .resend }
        return .wait
    }
}
