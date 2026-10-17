import Foundation

/// What the app and the bridge share: the native-messaging host's name and the files they hand each other
/// (docs/contract.md). The bridge writes today.json and empties requests/; the app reads today.json and fills
/// requests/.
enum NativeHost {
    static let name = "com.gatekeeper.helper"

    /// The extension IDs the host answers, besides any the app finds in the browsers' preferences.
    /// kfikbbdocggfgfhaegkgkfomhmacdbjp is the unpacked extension loaded from ~/gatekeeper-app/extension.
    static let knownExtensionIDs = ["kfikbbdocggfgfhaegkgkfomhmacdbjp"]

    static let bridgeExecutable = "gatekeeper-bridge"

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Gatekeeper", isDirectory: true)
    }

    static var todayFile: URL { folder.appendingPathComponent("today.json") }
    static var requestsFolder: URL { folder.appendingPathComponent("requests", isDirectory: true) }

    /// A Chrome extension ID: 32 letters from a to p.
    static func isExtensionID(_ s: String) -> Bool {
        s.count == 32 && s.allSatisfy { ("a"..."p").contains($0) }
    }
}
