import Foundation

/// What the app and the bridges share: the native-messaging host's name and the files they hand each other
/// (docs/contract.md). Each bridge (the Chrome/Brave tool and the Safari extension) writes its browser's snapshot to
/// snapshots/<browser>.json and claims linked.json if no browser has; the app follows the linked browser only,
/// and fills requests/, which only the linked browser is handed.
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

    static var snapshotsFolder: URL { folder.appendingPathComponent("snapshots", isDirectory: true) }
    static var requestsFolder: URL { folder.appendingPathComponent("requests", isDirectory: true) }
    static var linkedFile: URL { folder.appendingPathComponent("linked.json") }
    /// Where the bridge wrote before the Mac followed one browser; removed by the app at launch.
    static var oldTodayFile: URL { folder.appendingPathComponent("today.json") }

    /// The name a browser's snapshot is kept under: its bundle ID, or the extension ID when the bridge could not
    /// tell which browser called.
    static func key(browser: String?, extensionId: String?) -> String {
        let raw = browser ?? extensionId.map { "ext-" + $0 } ?? "unknown"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return String(String.UnicodeScalarView(raw.unicodeScalars.filter { allowed.contains($0) }))
    }

    static func snapshotFile(_ key: String) -> URL { snapshotsFolder.appendingPathComponent(key + ".json") }

    /// The browser the Mac follows, or nil if none has connected yet.
    static func linked() -> String? {
        guard let data = try? Data(contentsOf: linkedFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["browser"] as? String
    }

    /// Makes `key` the followed browser if none is, atomically, so two browsers calling at once cannot both win.
    /// Returns the followed browser.
    static func claimLinked(_ key: String) -> String {
        if let current = linked() { return current }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let body = (try? JSONSerialization.data(withJSONObject: ["browser": key])) ?? Data()
        let fd = open(linkedFile.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        if fd >= 0 {
            body.withUnsafeBytes { _ = write(fd, $0.baseAddress, body.count) }
            close(fd)
            return key
        }
        return linked() ?? key
    }

    /// The app's Settings picks another browser to follow.
    static func setLinked(_ key: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: ["browser": key]) {
            try? data.write(to: linkedFile, options: .atomic)
        }
    }

    /// The browsers that have sent a snapshot, newest first.
    static func seenBrowsers() -> [(key: String, at: Date)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: snapshotsFolder.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            let url = snapshotsFolder.appendingPathComponent(name)
            guard let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
            return (String(name.dropLast(5)), date)
        }.sorted { $0.at > $1.at }
    }

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
