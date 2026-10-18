import Foundation

/// One exchange with the extension over native messaging (docs/contract.md), shared by the Chrome/Brave bridge tool
/// and the Safari extension's handler.
///
/// Since 0.3 the account on the relay carries Today and exam mode, so the bridge no longer stores snapshots or hands
/// over requests. It does two things that must be instant on this Mac: while exam mode is on it makes sure
/// Gatekeeper runs (QA round 2, H3), and when the extension sends a pairing code and the Mac has not joined the
/// account yet, it keeps the code so the Mac joins the same account without the user typing it.
enum BridgeCore {
    struct Result {
        var reply: [String: Any]
        /// Exam mode on in the snapshot, until then: the caller makes sure the app runs.
        var examUntil: Date?
    }

    /// The version of the Mac app and of the contract it reads, sent with every reply (QA round 2, M11).
    static func macInfo(appVersion: String?) -> [String: Any] {
        ["version": appVersion ?? "unknown", "reads": [1], "joined": NativeHost.macJoined]
    }

    static func handle(_ message: Any?, callerID: String?, browser: String?, appVersion: String?) -> Result {
        let mac = macInfo(appVersion: appVersion)
        func refuse(_ error: String, _ more: [String: Any] = [:]) -> Result {
            Result(reply: ["ok": false, "error": error, "mac": mac].merging(more) { a, _ in a }, examUntil: nil)
        }
        guard let raw = message as? [String: Any], raw["type"] as? String == "snapshot" else {
            return refuse("bad_message", ["reason": "not a snapshot"])
        }
        guard (raw["v"] as? NSNumber)?.intValue == 1 else { return refuse("unknown_version") }

        let snapshot: Snapshot
        do {
            let data = try JSONSerialization.data(withJSONObject: raw)
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            return refuse("bad_message", ["reason": String(describing: error).prefix(300).description])
        }

        if let code = raw["pairCode"] as? String, code.count == 6, code.allSatisfy(\.isNumber), !NativeHost.macJoined {
            NativeHost.savePairCode(code)
        }
        let examUntil = snapshot.exam.map { Date(timeIntervalSince1970: $0.until / 1000) }.flatMap { $0 > Date() ? $0 : nil }
        return Result(reply: ["ok": true, "v": 1, "mac": mac], examUntil: examUntil)
    }
}
