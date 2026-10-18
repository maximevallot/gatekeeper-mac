// gatekeeper-bridge: the native-messaging host the Gatekeeper extension calls from Chrome and Brave
// (docs/contract.md). The browser starts it for each message with the caller's origin as its argument, writes one
// message to its input (a 4-byte length, then JSON) and reads one reply the same way. The exchange itself is
// BridgeCore, shared with the Safari extension.

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

/// Gatekeeper.app, two folders up from this tool (Contents/MacOS/gatekeeper-bridge).
let appURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let appVersion = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

guard let caller = callerID() else { reply(["ok": false, "error": "bad_origin", "mac": BridgeCore.macInfo(appVersion: appVersion)]) }
guard let data = readMessage(), let message = try? JSONSerialization.jsonObject(with: data) else {
    reply(["ok": false, "error": "bad_message", "mac": BridgeCore.macInfo(appVersion: appVersion)])
}
let result = BridgeCore.handle(message, callerID: caller, browser: callerBrowser(), appVersion: appVersion)
// Exam mode is on and Gatekeeper is not running (force-quit, or not yet opened): open it, so the Mac keeps
// enforcing (QA round 2, H3). The browser calls every minute.
if result.examUntil != nil,
   NSRunningApplication.runningApplications(withBundleIdentifier: NativeHost.appBundleID).isEmpty {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in done.signal() }
    _ = done.wait(timeout: .now() + 2)
}
reply(result.reply)
