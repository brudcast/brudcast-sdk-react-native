import Foundation
import Combine
import UserNotifications
import Brudcast

/// The Swift side of the push TurboModule: registers the native push module, forwards JavaScript
/// calls to it, and routes the notification handler and the permission status to JavaScript. The
/// Objective-C++ module owns one per JavaScript runtime and calls it on the main queue.
@objc(RNBrudcastPushBridge)
public final class RNBrudcastPushBridge: NSObject {
    /// The runtime whose JavaScript set the notification handler, so an old runtime cannot answer.
    private static weak var handlerOwner: RNBrudcastPushBridge?

    /// Sends a notification request to JavaScript.
    @objc public var emitNotificationRequest: ((NSDictionary) -> Void)?

    /// Sends a new permission status to JavaScript.
    @objc public var emitPermission: ((String) -> Void)?

    private var pending: [String: (BrudcastNotificationDecision) -> Void] = [:]
    private var permissionSubscription: AnyCancellable?

    /// Adds the native push module to the registry `initialize` reads, and arranges for the
    /// notification center proxy to install itself at launch, when the pod loads.
    @objc public static func registerModule() {
        RNBrudcastModuleRegistry.register(BrudcastPush.module)
        RNBrudcastNotificationCenterProxy.installAutomatically()
    }

    /// Starts sending the permission status to JavaScript.
    @objc public func moduleCreated() {
        permissionSubscription = Brudcast.push.permissionPublisher
            .removeDuplicates()
            .sink { [weak self] status in self?.emitPermission?(status.name) }
    }

    /// Lets go of this runtime: the notification handler is removed, and notifications it never
    /// answered show.
    @objc public func invalidate() {
        permissionSubscription = nil
        clearNotificationHandler()
        let waiting = pending.values
        pending.removeAll()
        waiting.forEach { $0(.show) }
    }

    @objc public func setToken(_ token: String) {
        Brudcast.push.setToken(token)
    }

    @objc public func requestPermission(provisional: Bool, completion: @escaping (String) -> Void) {
        Brudcast.push.requestPermission(provisional: provisional) { status in
            completion(status.name)
        }
    }

    @objc public func permissionStatus() -> String {
        Brudcast.push.permissionStatus.name
    }

    @objc public func setNotificationHandlerEnabled(_ enabled: Bool) {
        guard enabled else { return clearNotificationHandler() }
        Self.handlerOwner = self
        Brudcast.push.setAsyncNotificationHandler { notification, decide in
            guard let owner = Self.handlerOwner, let emit = owner.emitNotificationRequest else { return decide(.show) }
            let requestId = UUID().uuidString
            owner.pending[requestId] = decide
            emit(["requestId": requestId, "notification": notification.dictionary] as NSDictionary)
        }
    }

    /// Answers a notification request with the JavaScript handler's decision.
    ///
    /// - Parameters:
    ///   - requestId: The request's id.
    ///   - decision: `show` or `suppress`.
    @objc public func resolveNotification(requestId: String, decision: String) {
        pending.removeValue(forKey: requestId)?(decision == "suppress" ? .suppress : .show)
    }

    private func clearNotificationHandler() {
        guard Self.handlerOwner === self else { return }
        Self.handlerOwner = nil
        Brudcast.push.setAsyncNotificationHandler(nil)
    }
}

private extension BrudcastPushPermission {
    var name: String {
        switch self {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        }
    }
}

private extension BrudcastPushNotification {
    /// The notification as the spec's `NativePushNotification` describes it.
    var dictionary: NSDictionary {
        var result: [String: Any] = ["messageId": messageId, "data": data]
        if let campaignId = campaignId {
            result["campaignId"] = campaignId
        }
        if let applicationId = applicationId {
            result["applicationId"] = applicationId
        }
        if let title = title {
            result["title"] = title
        }
        if let body = body {
            result["body"] = body
        }
        if let clickURL = clickURL {
            result["clickUrl"] = clickURL.absoluteString
        }
        return result as NSDictionary
    }
}
