import Foundation

/// One exchange with the extension (docs/contract.md), shared by the Chrome/Brave bridge tool and the Safari
/// extension's handler.
///
/// A snapshot is accepted only if the Mac can read it (the same `Snapshot` type the app uses). It is kept as its
/// browser's own file, snapshots/<browser>.json. The first browser to connect becomes the one the Mac follows
/// (linked.json; Settings can change it); any other browser is answered `other_browser_linked` and is handed no
/// request, so two browsers can no longer end or steal each other's exam mode (QA round 2, C2, H1).
enum BridgeCore {
    struct Result {
        var reply: [String: Any]
        /// Exam mode on in the followed browser's snapshot, until then: the caller makes sure the app runs.
        var examUntil: Date?
    }

    /// The version of the Mac app and of the contract it reads, sent with every reply so either side can say which
    /// one needs updating (QA round 2, M11).
    static func macInfo(appVersion: String?) -> [String: Any] {
        ["version": appVersion ?? "unknown", "reads": [1]]
    }

    static func handle(_ message: Any?, callerID: String?, browser: String?, appVersion: String?) -> Result {
        let mac = macInfo(appVersion: appVersion)
        func refuse(_ error: String, _ more: [String: Any] = [:]) -> Result {
            Result(reply: ["ok": false, "error": error, "mac": mac].merging(more) { a, _ in a }, examUntil: nil)
        }
        guard var raw = message as? [String: Any], raw["type"] as? String == "snapshot" else {
            return refuse("bad_message", ["reason": "not a snapshot"])
        }
        guard (raw["v"] as? NSNumber)?.intValue == 1 else { return refuse("unknown_version") }
        if raw["extensionId"] == nil, let id = callerID { raw["extensionId"] = id }
        if raw["browser"] == nil, let b = browser { raw["browser"] = b }

        let data: Data
        let snapshot: Snapshot
        do {
            data = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            return refuse("bad_message", ["reason": String(describing: error).prefix(300).description])
        }

        let key = NativeHost.key(browser: raw["browser"] as? String, extensionId: raw["extensionId"] as? String)
        do {
            try FileManager.default.createDirectory(at: NativeHost.snapshotsFolder, withIntermediateDirectories: true)
            try data.write(to: NativeHost.snapshotFile(key), options: .atomic)
        } catch {
            return refuse("write_failed")
        }

        let followed = NativeHost.claimLinked(key)
        guard followed == key else {
            return refuse("other_browser_linked", ["linked": followed, "linkedName": NativeHost.browserName(followed)])
        }
        let examUntil = snapshot.exam.map { Date(timeIntervalSince1970: $0.until / 1000) }.flatMap { $0 > Date() ? $0 : nil }
        return Result(reply: ["ok": true, "v": 1, "mac": mac, "requests": takeRequests()], examUntil: examUntil)
    }

    /// The requests the app queued, oldest first. Each is handed over once: its file is deleted here.
    static func takeRequests() -> [[String: Any]] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: NativeHost.requestsFolder.path) else { return [] }
        var out: [[String: Any]] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            let url = NativeHost.requestsFolder.appendingPathComponent(name)
            if let data = try? Data(contentsOf: url),
               let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                out.append(request)
            }
            try? fm.removeItem(at: url)
        }
        return out
    }
}
