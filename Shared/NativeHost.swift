import Foundation

/// What the app and the bridges share: the native-messaging host's name and Gatekeeper's folder (docs/contract.md).
/// Since 0.3 the account on the relay carries Today and exam mode; native messaging only reopens the Mac app while
/// exam mode is on, and hands over a pairing code so the Mac can join the account a browser is already in.
enum NativeHost {
    static let name = "com.gatekeeper.helper"

    /// The extension IDs the host answers, besides any the app finds in the browsers' preferences.
    /// kfikbbdocggfgfhaegkgkfomhmacdbjp is the unpacked extension loaded from ~/gatekeeper-app/extension.
    static let knownExtensionIDs = ["kfikbbdocggfgfhaegkgkfomhmacdbjp"]

    static let bridgeExecutable = "gatekeeper-bridge"
    static let appBundleID = "com.gatekeeper.mac"

    /// The user's real home folder. In the sandboxed Safari extension, FileManager's home is the sandbox's own
    /// container, which the app never reads (QA round 2, C1); the extension's entitlement lets it write to this
    /// one folder of the real home.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var folder: URL {
        // Tests point this at a scratch folder so they never touch the real files.
        if let dir = ProcessInfo.processInfo.environment["GATEKEEPER_FOLDER"] { return URL(fileURLWithPath: dir, isDirectory: true) }
        return realHome.appendingPathComponent("Library/Application Support/Gatekeeper", isDirectory: true)
    }

    /// A 6-digit code a browser of the account handed over, for the Mac to join with (pair.json).
    static var pairFile: URL { folder.appendingPathComponent("pair.json") }

    /// Files from 0.1 and 0.2, when the Mac followed one browser's snapshot.
    static func removeOldFiles() {
        for name in ["today.json", "linked.json", "snapshots", "requests"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// A code is good for 10 minutes on the account's side; one older than that here is not tried.
    static let pairCodeLife: TimeInterval = 600

    static func savePairCode(_ code: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let body: [String: Any] = ["code": code, "at": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            try? data.write(to: pairFile, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairFile.path)
        }
    }

    /// The handed-over code, once: it is deleted as it is read.
    static func takePairCode(now: Date = Date()) -> String? {
        guard let data = try? Data(contentsOf: pairFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        try? FileManager.default.removeItem(at: pairFile)
        guard let code = obj["code"] as? String, let at = obj["at"] as? Double,
              now.timeIntervalSince1970 - at < pairCodeLife else { return nil }
        return code
    }

    /// The Mac has joined the account (account.json exists).
    static var macJoined: Bool { FileManager.default.fileExists(atPath: folder.appendingPathComponent("account.json").path) }

    /// A short name for a browser key, for messages.
    static func browserName(_ key: String) -> String {
        switch key {
        case "com.brave.Browser": return "Brave"
        case "com.google.Chrome": return "Chrome"
        case "com.apple.Safari": return "Safari"
        case "com.microsoft.edgemac": return "Edge"
        case "com.vivaldi.Vivaldi": return "Vivaldi"
        default: return key
        }
    }

    /// A Chrome extension ID: 32 letters from a to p.
    static func isExtensionID(_ s: String) -> Bool {
        s.count == 32 && s.allSatisfy { ("a"..."p").contains($0) }
    }
}
