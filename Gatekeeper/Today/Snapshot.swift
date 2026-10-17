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

extension Snapshot {
    /// The screen in the design canvas: Social 9 of 15 left, Video spent, Games closed all day.
    static func sample(now: Date = Date()) -> Snapshot {
        Snapshot(
            v: 1, at: now.timeIntervalSince1970 * 1000, browser: nil, extensionId: nil, pages: nil,
            goal: "Finish problem set 4 by Thursday",
            reopensAt: Day.nextStart(after: now, hour: 4).timeIntervalSince1970 * 1000, waiting: false,
            kinds: [
                Kind(kind: "social", label: "Social media", short: "Social", minutes: 15, left: 9, status: "open", fraction: 0.6, exam: nil),
                Kind(kind: "video", label: "Video", short: "Video", minutes: 20, left: 0, status: "spent", fraction: 0, exam: nil),
                Kind(kind: "games", label: "Games", short: "Games", minutes: 0, left: 0, status: "closed", fraction: 0, exam: nil),
            ],
            exam: nil, watch: nil)
    }
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
