import AppKit

/// The browsers the Mac knows, and which one runs the Gatekeeper extension.
enum Browsers {
    /// Every browser exam mode may hide or quit, by bundle ID.
    static let known: [String: String] = [
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Google Chrome",
        "com.brave.Browser": "Brave Browser",
        "org.mozilla.firefox": "Firefox",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.operasoftware.Opera": "Opera",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "app.zen-browser.zen": "Zen",
        "com.kagi.kagimacOS": "Orion",
        "ai.perplexity.comet": "Comet",
        "com.openai.atlas": "ChatGPT Atlas",
    ]

    /// Chromium browsers that can run the extension, and where each keeps its profiles.
    static let chromium: [(bundleID: String, folder: String)] = [
        ("com.brave.Browser", "BraveSoftware/Brave-Browser"),
        ("com.google.Chrome", "Google/Chrome"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("company.thebrowser.Browser", "Arc/User Data"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
    ]

    struct Found: Equatable {
        var bundleID: String
        var extensionID: String
    }

    /// Finds the browser and ID of the Gatekeeper extension by reading each Chromium profile's preferences:
    /// an extension named Gatekeeper, or one loaded unpacked from a folder named gatekeeper-app.
    /// Used until the bridge reports both in the snapshot.
    static func findExtension() -> Found? {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        for (bundleID, folder) in chromium {
            let root = support.appendingPathComponent(folder)
            guard let profiles = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { continue }
            for profile in profiles where profile == "Default" || profile.hasPrefix("Profile ") {
                for file in ["Secure Preferences", "Preferences"] {
                    let url = root.appendingPathComponent(profile).appendingPathComponent(file)
                    if let id = gatekeeperID(inPreferences: url) { return Found(bundleID: bundleID, extensionID: id) }
                }
            }
        }
        return nil
    }

    private static func gatekeeperID(inPreferences url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = (json["extensions"] as? [String: Any])?["settings"] as? [String: Any]
        else { return nil }
        for (id, value) in settings {
            guard let entry = value as? [String: Any] else { continue }
            let name = (entry["manifest"] as? [String: Any])?["name"] as? String
            let path = entry["path"] as? String ?? ""
            if name == "Gatekeeper" || path.hasSuffix("/gatekeeper-app/extension") { return id }
        }
        return nil
    }

    /// The Safari version of the extension, inside this app.
    static let safariExtensionID = "com.gatekeeper.mac.safari"

    static func name(_ bundleID: String) -> String {
        known[bundleID] ?? bundleID
    }

    /// Opens a page of the extension in the browser that runs it. `base` is the extension's own address when it
    /// sent one (Safari's has no ID in it); otherwise chrome-extension://<id>/.
    static func open(page: String, extensionID: String, base: String? = nil, in bundleID: String) {
        let root = base ?? "chrome-extension://\(extensionID)/"
        guard let url = URL(string: root + page),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
    }
}
