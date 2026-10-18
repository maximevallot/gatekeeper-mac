import Foundation
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
        let reply = BridgeCore.handle(message, callerID: nil, browser: "com.apple.Safari")
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
