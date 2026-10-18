import Foundation

/// One exchange with the extension (docs/contract.md), shared by the Chrome/Brave bridge tool and the Safari
/// extension's handler: save the snapshot to today.json and hand over the requests the app queued.
enum BridgeCore {
    /// The reply to one message. `callerID` and `browser` fill the snapshot's fields when the extension leaves
    /// them out.
    static func handle(_ message: Any?, callerID: String?, browser: String?) -> [String: Any] {
        guard var snapshot = message as? [String: Any], snapshot["type"] as? String == "snapshot" else {
            return ["ok": false, "error": "bad_message"]
        }
        guard (snapshot["v"] as? NSNumber)?.intValue == 1 else { return ["ok": false, "error": "unknown_version"] }
        if snapshot["extensionId"] == nil, let id = callerID { snapshot["extensionId"] = id }
        if snapshot["browser"] == nil, let b = browser { snapshot["browser"] = b }
        do {
            try FileManager.default.createDirectory(at: NativeHost.folder, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .withoutEscapingSlashes])
            try data.write(to: NativeHost.todayFile, options: .atomic)
        } catch {
            return ["ok": false, "error": "write_failed"]
        }
        return ["ok": true, "v": 1, "requests": takeRequests()]
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
