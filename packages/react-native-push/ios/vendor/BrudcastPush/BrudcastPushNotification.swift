import Foundation

/// A push notification Brudcast sent, read from its payload.
public struct BrudcastPushNotification: Equatable {
    public let messageId: String
    public let campaignId: String?
    public let applicationId: String?
    public let title: String?
    public let body: String?
    public let clickURL: URL?
    /// The custom data the campaign carried, without the Brudcast keys.
    public let data: [String: String]

    /// Reads a notification payload.
    ///
    /// - Parameter userInfo: The payload, such as `UNNotificationContent.userInfo`.
    /// - Returns: The notification, or nil when the payload has no `bc_mid` and so is not from Brudcast.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let messageId = userInfo[BrudcastPushKeys.messageId] as? String, !messageId.isEmpty else { return nil }
        self.messageId = messageId
        campaignId = userInfo[BrudcastPushKeys.campaignId] as? String
        applicationId = userInfo[BrudcastPushKeys.applicationId] as? String
        clickURL = (userInfo[BrudcastPushKeys.clickURL] as? String).flatMap { URL(string: $0) }

        let aps = userInfo["aps"] as? [String: Any]
        if let alert = aps?["alert"] as? [String: Any] {
            title = alert["title"] as? String
            body = alert["body"] as? String
        } else {
            title = nil
            body = aps?["alert"] as? String
        }

        var data: [String: String] = [:]
        let reserved: Set<String> = [BrudcastPushKeys.messageId, BrudcastPushKeys.campaignId, BrudcastPushKeys.applicationId, BrudcastPushKeys.clickURL, "aps", "fcm_options"]
        for (key, value) in userInfo {
            guard let key = key as? String, !reserved.contains(key), !key.hasPrefix("gcm."), !key.hasPrefix("google."),
                  let string = value as? String else { continue }
            data[key] = string
        }
        self.data = data
    }
}
