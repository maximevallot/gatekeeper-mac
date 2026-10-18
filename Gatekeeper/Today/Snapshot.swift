import Foundation

/// What the extension tells the Mac about today, as docs/contract.md defines it (version 1): the engine's
/// todaySummary, plus the pages and exam mode. The bridge writes it to today.json; the app only reads it and works
/// nothing out from it. Times are milliseconds since 1970, as the extension's engine keeps them.
struct Snapshot: Codable, Equatable {
    struct Kind: Codable, Equatable, Identifiable {
        var kind: String
        var label: String
        var short: String?
        var minutes: Int
        var left: Int
        var status: String // "open", "spent" or "closed"
        var fraction: Double?
        /// Closed by exam mode rather than by its own budget.
        var exam: Bool?
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
    var goal: String?
    var reopensAt: Double
    var waiting: Bool?
    var kinds: [Kind]
    var exam: Exam?
    var watch: Watch?

    var reopens: Date { Date(timeIntervalSince1970: reopensAt / 1000) }
}

/// One ring on the Today screen, exactly as the engine decided it.
struct Ring: Identifiable, Equatable {
    enum State: Equatable {
        case open(minutesLeft: Int, fraction: Double)
        case spent(reopens: Date)
        case closedAllDay
    }

    let id: String
    let name: String
    let state: State

    static func rings(from s: Snapshot) -> [Ring] {
        s.kinds.map { k in
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
                let fraction = k.fraction ?? (k.minutes > 0 ? Double(k.left) / Double(k.minutes) : 0)
                return Ring(id: k.kind, name: name, state: .open(minutesLeft: k.left, fraction: min(1, max(0, fraction))))
            }
        }
    }
}

enum Day {
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

    /// Exam mode as the engine last said, even if the browser has since closed: it runs to its end.
    static func confirmedExam(_ s: Snapshot?, now: Date) -> Date? {
        guard let exam = s?.exam else { return nil }
        let until = Date(timeIntervalSince1970: exam.until / 1000)
        return until > now ? until : nil
    }

    /// What the Mac enforces: the engine's exam mode, or a start the browser is confirming.
    static func enforcedExam(_ s: Snapshot?, pendingUntil: Date?, now: Date) -> Date? {
        if let until = confirmedExam(s, now: now) { return until }
        if let p = pendingUntil, p > now { return p }
        return nil
    }

    enum PendingStep: Equatable { case wait, confirmed, drop, resend }

    /// What to do with a start of exam mode asked for on the Mac. Confirmed once a snapshot shows it (the engine
    /// holds it now). Dropped when the browser stops answering (the Mac has no exam mode of its own), after ten
    /// minutes unconfirmed, or at its end. Sent again if the browser took it and two minutes passed with no sign.
    static func pendingStep(until: Date, asked: Date, queued: Date, stillQueued: Bool,
                            snapshot: Snapshot?, connected: Bool, now: Date) -> PendingStep {
        if let exam = snapshot?.exam, exam.until >= until.timeIntervalSince1970 * 1000 - 1000 { return .confirmed }
        if !connected || now.timeIntervalSince(asked) > pendingFor || until <= now { return .drop }
        if !stillQueued && now.timeIntervalSince(queued) > resendAfter { return .resend }
        return .wait
    }
}
