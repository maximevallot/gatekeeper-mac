import Foundation

/// This Mac's membership in the person's Gatekeeper account: the relay address and the device key the account
/// gave it when it joined with a code (~/brain/outputs/html/2026-10-17-gatekeeper-one-per-person.html, step 5).
///
/// Kept in a file only this user can read (0600) in Gatekeeper's folder, not in the Keychain: the app is signed
/// ad hoc until the paid developer account exists, every build has a new signature, and the Keychain would ask the
/// user to allow each new build. Moving the key to the Keychain is for the signed app.
struct AccountMembership: Codable, Equatable {
    var relay: String
    var deviceId: String
    var deviceKey: String
    var accountId: String?
    var joinedAt: Date
}

enum AccountStore {
    static var file: URL { NativeHost.folder.appendingPathComponent("account.json") }

    static func load() -> AccountMembership? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AccountMembership.self, from: data)
    }

    static func save(_ m: AccountMembership) throws {
        try FileManager.default.createDirectory(at: NativeHost.folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(m)
        try data.write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Leaving, or the account removed this device: the Mac carries on with what it last knew (exam mode held
    /// to its end) and asks for a code again.
    static func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}
