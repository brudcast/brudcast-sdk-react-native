import Foundation
import UserNotifications

/// A notification service extension that attaches the notification's image and records that the
/// device received it.
///
/// Make your extension's principal class a subclass and override `appGroupIdentifier` with the App
/// Group you pass to `BrudcastOptions.appGroupIdentifier`. Notifications that are not from Brudcast
/// still get their image attached.
open class BrudcastNotificationServiceExtension: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var task: URLSessionDownloadTask?

    /// The App Group shared with the app. Nil skips recording `push_received`.
    open var appGroupIdentifier: String? {
        nil
    }

    open override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
        bestAttempt = content
        let userInfo = request.content.userInfo

        if let group = appGroupIdentifier, let messageId = userInfo[BrudcastPushKeys.messageId] as? String {
            var properties: [String: String] = [:]
            properties["campaignId"] = userInfo[BrudcastPushKeys.campaignId] as? String
            BrudcastSharedEvents.append(
                type: "push_received",
                messageId: messageId,
                properties: properties,
                appGroupIdentifier: group,
                id: BrudcastSharedEvents.receivedEventId(messageId: messageId)
            )
        }

        guard let content = content, let imageURL = Self.imageURL(in: userInfo) else {
            deliver()
            return
        }
        task = URLSession.shared.downloadTask(with: imageURL) { [weak self] location, response, _ in
            defer { self?.deliver() }
            guard let location = location,
                  Self.fileSize(location) <= Self.maxImageBytes,
                  let attachment = Self.attachment(from: location, url: imageURL, mimeType: response?.mimeType) else { return }
            content.attachments = [attachment]
        }
        task?.resume()
    }

    open override func serviceExtensionTimeWillExpire() {
        task?.cancel()
        deliver()
    }

    private func deliver() {
        guard let handler = contentHandler, let content = bestAttempt else { return }
        contentHandler = nil
        handler(content)
    }

    /// Finds the image FCM put in the payload.
    ///
    /// - Parameter userInfo: The notification's payload.
    /// - Returns: The image URL, or nil.
    static func imageURL(in userInfo: [AnyHashable: Any]) -> URL? {
        let options = userInfo["fcm_options"] as? [String: Any]
        let raw = options?["image"] as? String ?? userInfo["image"] as? String
        guard let string = raw, let url = URL(string: string), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    /// The largest image Apple accepts as a notification attachment.
    static let maxImageBytes = 10 * 1_024 * 1_024

    static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max
    }

    static func attachment(from location: URL, url: URL, mimeType: String?) -> UNNotificationAttachment? {
        let ext: String
        switch mimeType {
        case "image/png": ext = "png"
        case "image/gif": ext = "gif"
        case "image/jpeg", "image/jpg": ext = "jpg"
        default: ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.moveItem(at: location, to: target)
            return try UNNotificationAttachment(identifier: "image", url: target, options: nil)
        } catch {
            return nil
        }
    }
}

/// The data keys Brudcast adds to every push notification.
public enum BrudcastPushKeys {
    public static let messageId = "bc_mid"
    public static let campaignId = "bc_cid"
    public static let applicationId = "bc_app"
    public static let clickURL = "click_url"
}
