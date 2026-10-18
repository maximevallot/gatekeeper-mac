import Foundation

/// The Mac's side of the account API on the relay. Every path and field name the contract fixes is in `API`, so
/// a change to the contract is a change here only.
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
        return URL(string: "https://gatekeeper-relay.mvallot22.workers.dev")!
    }

    // MARK: Join

    func join(code: String) async throws -> AccountMembership {
        let digits = code.filter(\.isNumber)
        let body: [String: Any] = [
            "v": API.contract, "code": digits,
            "device": ["name": API.deviceName, "kind": API.deviceKind],
        ]
        let (status, json) = try await post(API.join, body: body, key: nil)
        switch status {
        case 200..<300:
            return try Self.membership(from: json, relay: relay)
        case 400, 403, 404, 409, 410:
            throw Failure.badCode(json["error"] as? String ?? "bad_code")
        default:
            throw Failure.server(status, json["error"] as? String ?? "")
        }
    }

    static func membership(from json: [String: Any], relay: URL) throws -> AccountMembership {
        guard let deviceId = json["deviceId"] as? String, let key = json["deviceKey"] as? String else {
            throw Failure.badReply("no deviceId or deviceKey")
        }
        return AccountMembership(relay: relay.absoluteString, deviceId: deviceId, deviceKey: key,
                                 accountId: json["accountId"] as? String, joinedAt: Date())
    }

    // MARK: Sync

    struct Synced {
        var snapshot: Snapshot
        /// Ids of the requests the account took, so the Mac stops sending them.
        var taken: [String]
    }

    /// Sends the Mac's requests (only tightenings: exam.start) and its clock; gets the account's Today back.
    func sync(_ m: AccountMembership, requests: [[String: Any]]) async throws -> Synced {
        let body: [String: Any] = [
            "v": API.contract, "deviceId": m.deviceId, "clock": (Date().timeIntervalSince1970 * 1000).rounded(),
            "spans": [], "requests": requests,
        ]
        let (status, json) = try await post(API.sync, body: body, key: m.deviceKey)
        switch status {
        case 200..<300:
            return try Self.synced(from: json)
        case 401, 403:
            throw Failure.removed
        default:
            throw Failure.server(status, json["error"] as? String ?? "")
        }
    }

    static func synced(from json: [String: Any]) throws -> Synced {
        guard let snap = json["snapshot"] else { throw Failure.badReply("no snapshot") }
        let data = try JSONSerialization.data(withJSONObject: snap)
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            let taken = (json["taken"] as? [String]) ?? []
            return Synced(snapshot: snapshot, taken: taken)
        } catch {
            throw Failure.badReply(String(describing: error).prefix(200).description)
        }
    }

    // MARK: Leave

    func leave(_ m: AccountMembership) async {
        _ = try? await post(API.leave, body: ["v": API.contract, "deviceId": m.deviceId], key: m.deviceKey)
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
