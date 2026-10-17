// gatekeeper-bridge: the native-messaging host the Gatekeeper extension calls (docs/contract.md).
// The browser starts it for each message with the caller's origin as its argument, writes one message to its
// input (a 4-byte length, then JSON) and reads one reply the same way. It saves the snapshot to today.json,
// hands over the requests the app queued, and exits.

import AppKit

let maxMessage = 1 << 20

func readMessage() -> Data? {
    let input = FileHandle.standardInput
    let header = input.readData(ofLength: 4)
    guard header.count == 4 else { return nil }
    let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
    guard length > 0, length <= maxMessage else { return nil }
    let body = input.readData(ofLength: length)
    return body.count == length ? body : nil
}

func reply(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{\"ok\":false}".utf8)
    var length = UInt32(data.count).littleEndian
    FileHandle.standardOutput.write(Data(bytes: &length, count: 4))
    FileHandle.standardOutput.write(data)
    exit(0)
}

/// The origin the browser passes: chrome-extension://<id>/
func callerID() -> String? {
    guard CommandLine.arguments.count > 1 else { return nil }
    let origin = CommandLine.arguments[1]
    let prefix = "chrome-extension://"
    guard origin.hasPrefix(prefix) else { return nil }
    let id = origin.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return NativeHost.isExtensionID(id) ? id : nil
}

/// The browser that started this process: the first ancestor that is an app with a bundle ID.
func callerBrowser() -> String? {
    var pid = getppid()
    for _ in 0..<4 where pid > 1 {
        if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier { return id }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        pid = info.kp_eproc.e_ppid
    }
    return nil
}

/// The requests the app queued, oldest first. Each is handed over once: its file is deleted here.
func takeRequests() -> [[String: Any]] {
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

guard let caller = callerID() else { reply(["ok": false, "error": "bad_origin"]) }
guard let data = readMessage(),
      var message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      message["type"] as? String == "snapshot"
else { reply(["ok": false, "error": "bad_message"]) }
guard message["v"] as? Int == 1 else { reply(["ok": false, "error": "unknown_version"]) }

if message["extensionId"] == nil { message["extensionId"] = caller }
if message["browser"] == nil, let browser = callerBrowser() { message["browser"] = browser }

do {
    try FileManager.default.createDirectory(at: NativeHost.folder, withIntermediateDirectories: true)
    let out = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])
    try out.write(to: NativeHost.todayFile, options: .atomic)
} catch {
    reply(["ok": false, "error": "write_failed"])
}

reply(["ok": true, "v": 1, "requests": takeRequests()])
