import Foundation

/// What the extension tells the Mac about today, as docs/contract.md defines it (version 1). The bridge writes
/// it to today.json; the app only reads it. Times are milliseconds since 1970, as the extension's engine keeps them.
struct Snapshot: Codable, Equatable {
    struct Kind: Codable, Equatable, Identifiable {
        var kind: String
        var label: String
        var minutes: Int
        var usedSeconds: Double
        var id: String { kind }
    }

    struct Pages: Codable, Equatable {
        var rules: String?
        var talk: String?
        var week: String?
    }

    struct Pending: Codable, Equatable {
        var from: Double
    }

    struct Exam: Codable, Equatable {
        var until: Double
        var goal: String?
    }

    var v: Int
    var at: Double
    var browser: String?
    var extensionId: String?
    var pages: Pages?
    var goal: String?
    var dayStart: Int?
    var endsAt: Double
    var kinds: [Kind]
    var pending: Pending?
    var exam: Exam?
}

extension Snapshot {
    /// The screen in the design canvas: Social 9 of 15 left, Video spent, Games closed all day.
    static func sample(now: Date = Date()) -> Snapshot {
        let ms = now.timeIntervalSince1970 * 1000
        return Snapshot(
            v: 1, at: ms, browser: nil, extensionId: nil, pages: nil,
            goal: "Finish problem set 4 by Thursday", dayStart: 4,
            endsAt: Day.nextStart(after: now, hour: 4).timeIntervalSince1970 * 1000,
            kinds: [
                Kind(kind: "social", label: "Social media", minutes: 15, usedSeconds: 6 * 60),
                Kind(kind: "video", label: "Video", minutes: 20, usedSeconds: 20 * 60),
                Kind(kind: "games", label: "Games", minutes: 0, usedSeconds: 0),
            ],
            pending: nil, exam: nil)
    }
}

/// One ring on the Today screen.
struct Ring: Identifiable, Equatable {
    enum State: Equatable {
        case open(minutesLeft: Int, fraction: Double)
        case spent(reopens: Date)
        case closedAllDay
    }

    let id: String
    let name: String
    let state: State

    /// The short names the design uses under each ring.
    static func shortName(kind: String, label: String) -> String {
        switch kind {
        case "social": return "Social"
        default: return label
        }
    }

    static func rings(from s: Snapshot, now: Date) -> [Ring] {
        let endsAt = Date(timeIntervalSince1970: s.endsAt / 1000)
        let newDay = now >= endsAt // the snapshot is from a day that has ended: every budget is whole again
        let reopens = newDay ? Day.nextStart(after: now, hour: s.dayStart ?? 4) : endsAt
        return s.kinds.map { k in
            let name = shortName(kind: k.kind, label: k.label)
            if k.minutes <= 0 { return Ring(id: k.kind, name: name, state: .closedAllDay) }
            let budget = Double(k.minutes * 60)
            let used = newDay ? 0 : min(k.usedSeconds, budget)
            if used >= budget { return Ring(id: k.kind, name: name, state: .spent(reopens: reopens)) }
            let left = Int(((budget - used) / 60).rounded(.up))
            return Ring(id: k.kind, name: name, state: .open(minutesLeft: left, fraction: (budget - used) / budget))
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
