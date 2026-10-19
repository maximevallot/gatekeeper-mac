import Foundation

/// What tells this build apart from the 0.2 app on the same Mac. This is the 0.3 test build (branch `account`),
/// which runs beside Maxime's 0.2 build against the staging relay: its own bundle IDs, folder, native-messaging
/// host and extension, so the two never touch each other's files, login item or Brave entry. For a release, these
/// go back to the plain names.
enum Identity {
    static let appBundleID = "com.gatekeeper.mac.test"
    static let safariExtensionID = "com.gatekeeper.mac.test.safari"
    /// In ~/Library/Application Support. Also in the Safari extension's entitlement (project.yml).
    static let folderName = "Gatekeeper Test"
    /// The native-messaging host the 0.3 extension calls in Brave and Chrome.
    static let hostName = "com.gatekeeper.helper.test"
    /// The 0.3 extension loaded unpacked from ~/gatekeeper-app-0.3/extension (its ID comes from that path).
    static let extensionIDs = ["hkghdhjbbcokmgaaldcfpojbcahajbhe"]
    static let extensionPathSuffixes = ["/gatekeeper-app-0.3/extension"]
    /// A store or packed build records its manifest name; an unpacked one often does not.
    static let extensionNamePrefixes = ["Gatekeeper 0.3"]
    /// The staging relay, separate from the one 0.2 and the store build use.
    static let relay = "https://gatekeeper-relay-staging.mvallot22.workers.dev"
    /// The test build does not add itself to Login Items, so it never starts beside 0.2 at login.
    static let opensAtLoginByDefault = false
}
