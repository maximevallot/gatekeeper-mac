import Foundation

/// Tells each Chromium browser where the bridge is: a host manifest in the browser's NativeMessagingHosts
/// folder, rewritten at every launch so it follows the app wherever it was built or moved. Only browsers
/// installed on this Mac (their folder exists) get one.
enum HostInstaller {
    static let browserFolders = [
        "BraveSoftware/Brave-Browser", "Google/Chrome", "Google/Chrome Beta", "Chromium", "Microsoft Edge", "Vivaldi",
    ]

    static func install(extraIDs: [String]) {
        let bridge = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(NativeHost.bridgeExecutable)")
        guard FileManager.default.isExecutableFile(atPath: bridge.path) else {
            NSLog("Gatekeeper: no bridge at \(bridge.path)")
            return
        }
        let ids = Array(Set(NativeHost.knownExtensionIDs + extraIDs.filter(NativeHost.isExtensionID))).sorted()
        let manifest: [String: Any] = [
            "name": NativeHost.name,
            "description": "Gatekeeper for Mac",
            "path": bridge.path,
            "type": "stdio",
            "allowed_origins": ids.map { "chrome-extension://\($0)/" },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return }

        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        for folder in browserFolders {
            let browser = support.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: browser.path) else { continue }
            let hosts = browser.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            let file = hosts.appendingPathComponent("\(NativeHost.name).json")
            if (try? Data(contentsOf: file)) == data { continue }
            do {
                try FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
            } catch {
                NSLog("Gatekeeper: host manifest for \(folder): \(error.localizedDescription)")
            }
        }
    }
}
