import AppKit
import SafariServices

/// The Safari extension's side of the Mac link. In Safari, the extension's sendNativeMessage comes here, to the
/// app that contains it, whatever host name it names; the exchange is the same as the Chrome/Brave bridge's
/// (BridgeCore, docs/contract.md).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message: Any?
        if #available(macOS 11.0, *) {
            message = item?.userInfo?[SFExtensionMessageKey]
        } else {
            message = item?.userInfo?["message"]
        }
        // Gatekeeper.app, four folders up: Contents/PlugIns/GatekeeperSafari.appex/Contents/MacOS/GatekeeperSafari.
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let version = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let result = BridgeCore.handle(message, callerID: nil, browser: "com.apple.Safari", appVersion: version)
        // Exam mode is on: make sure Gatekeeper runs (QA round 2, H3). The sandbox may refuse; then the Mac app
        // is reopened by the Chrome/Brave bridge or at the next login.
        if result.examUntil != nil,
           NSRunningApplication.runningApplications(withBundleIdentifier: NativeHost.appBundleID).isEmpty {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
        }
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: result.reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
