import Foundation

/// The Mac's side of the account API on the relay: ~/gatekeeper-relay docs/account-contract.md, version 1
/// (draft 1, 2026-10-18). Every path and field name the contract fixes is here, so a change to the contract is a
/// change in this file only.
struct AccountClient {
    enum API {
        static let contract = 1
        static let join = "/account/join"
        static let sync = "/account/sync"
        static let leave = "/account/leave"
        static let deviceName = "Gatekeeper for Mac"
        static let deviceKind = "mac"
    }

    enum Failure: Error, Equatable {
        /// The code was wrong, expired or already used; `reason` is the relay's word for which.
        case badCode(String)
        /// The account no longer knows this device: removed from another device, or the account was deleted.
        case removed
        /// No answer: offline, or the relay is down.
        case unreachable
        case server(Int, String)
        case badReply(String)
    }

    /// The relay: the deployed one, or another for testing (Settings › Advanced, or GATEKEEPER_RELAY).
    var relay: URL
    var session: URLSession = .shared

    static var defaultRelay: URL {
        if let env = ProcessInfo.processInfo.environment["GATEKEEPER_RELAY"], let url = URL(string: env) { return url }
        if let saved = UserDefaults.standard.string(forKey: "relayURL"), let url = URL(string: saved) { return url }
        return URL(string: Identity.relay)!
    }

    // MARK: Join

    struct Joined {
        var membership: AccountMembership
        var today: Snapshot?
    }

    /// Joins with the code another device shows. The Mac sends no state of its own: it has no rules to merge.
    func join(code: String) async throws -> Joined {
        let body: [String: Any] = [
            "v": API.contract, "code": code.filter(\.isNumber),
            "device": ["name": API.deviceName, "kind": API.deviceKind],
            "tz": TimeZone.current.identifier, "now": Self.millis(Date()), "want": ["today"],
        ]
        let (status, json) = try await post(API.join, body: body, key: nil)
        switch status {
        case 200..<300:
            return Joined(membership: try Self.membership(from: json, relay: relay), today: Self.today(from: json))
        case 400, 404, 429:
            throw Failure.badCode(json["error"] as? String ?? "bad_code")
        default:
            throw Failure.server(status, json["error"] as? String ?? "")
        }
    }

    static func membership(from json: [String: Any], relay: URL) throws -> AccountMembership {
        guard let device = json["device"] as? [String: Any],
              let deviceId = device["id"] as? String, let token = device["token"] as? String else {
            throw Failure.badReply("no device id or token")
        }
        return AccountMembership(relay: relay.absoluteString, deviceId: deviceId, deviceKey: token,
                                 accountId: json["accountId"] as? String, joinedAt: Date())
    }

    // MARK: Sync

    struct Synced {
        /// The account's copy version; sent back as `have`.
        var version: Int?
        /// Nothing changed since `have`: keep the last Today.
        var unchanged: Bool
        /// The account's Today (the native-messaging snapshot shape), when it sent one.
        var today: Snapshot?
        /// Exam mode read from the account's copy, for when no Today came with it.
        var examFromCopy: Snapshot.Exam?
        /// The answer to each request, by its id. An answered request is done; the Mac stops sending it.
        var results: [String: [String: Any]]
    }

    /// Sends the Mac's requests (it may only tighten: startExam) and its clock; gets the account's Today back.
    /// The Mac sends no spans: it is not a browser and counts no time.
    func sync(_ m: AccountMembership, have: Int?, requests: [[String: Any]]) async throws -> Synced {
        var body: [String: Any] = [
            "v": API.contract, "now": Self.millis(Date()), "tz": TimeZone.current.identifier,
            "spans": [], "requests": requests, "want": ["today"],
        ]
        if let have { body["have"] = have }
        let (status, json) = try await post(API.sync, body: body, key: m.deviceKey)
        switch status {
        case 200..<300:
            return try Self.synced(from: json)
        case 401, 410:
            // bad_token: removed from another device. account_deleted: the account is gone.
            throw Failure.removed
        default:
            throw Failure.server(status, json["error"] as? String ?? "")
        }
    }

    static func synced(from json: [String: Any]) throws -> Synced {
        var results: [String: [String: Any]] = [:]
        for r in (json["results"] as? [[String: Any]]) ?? [] {
            if let id = r["id"] as? String { results[id] = r }
        }
        let unchanged = json["unchanged"] as? Bool ?? false
        let today = Self.today(from: json)
        var examFromCopy: Snapshot.Exam?
        if let exam = ((json["copy"] as? [String: Any])?["rules"] as? [String: Any])?["exam"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: exam) {
            examFromCopy = try? JSONDecoder().decode(Snapshot.Exam.self, from: data)
        }
        if !unchanged, today == nil, json["copy"] == nil { throw Failure.badReply("no today and no copy") }
        return Synced(version: (json["version"] as? NSNumber)?.intValue, unchanged: unchanged, today: today,
                      examFromCopy: examFromCopy, results: results)
    }

    /// The `today` field: engine.snapshot() as the account computes it, in the native-messaging contract's shape.
    static func today(from json: [String: Any]) -> Snapshot? {
        guard let t = json["today"], let data = try? JSONSerialization.data(withJSONObject: t) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func millis(_ d: Date) -> Double { (d.timeIntervalSince1970 * 1000).rounded() }

    // MARK: Leave

    func leave(_ m: AccountMembership) async {
        _ = try? await post(API.leave, body: ["v": API.contract], key: m.deviceKey)
    }

    // MARK: HTTP

    private func post(_ path: String, body: [String: Any], key: String?) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: relay.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (status, json)
    }
}
