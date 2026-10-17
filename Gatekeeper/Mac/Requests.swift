import Foundation

/// The Mac's requests to the extension: one JSON file each in requests/, which the bridge hands over the next
/// time the extension calls it, then deletes (docs/contract.md).
enum Requests {
    static func queue(_ request: [String: Any]) {
        var r = request
        let id = UUID().uuidString
        r["id"] = id
        let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(id).json"
        do {
            try FileManager.default.createDirectory(at: NativeHost.requestsFolder, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])
            try data.write(to: NativeHost.requestsFolder.appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("Gatekeeper: request not queued: \(error.localizedDescription)")
        }
    }

    static func isQueued(type: String) -> Bool { !files(ofType: type).isEmpty }

    static func removeAll(ofType type: String) {
        for url in files(ofType: type) { try? FileManager.default.removeItem(at: url) }
    }

    private static func files(ofType type: String) -> [URL] {
        let folder = NativeHost.requestsFolder
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.map { folder.appendingPathComponent($0) }.filter { url in
            guard let data = try? Data(contentsOf: url),
                  let r = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return r["type"] as? String == type
        }
    }
}
