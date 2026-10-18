import Foundation
import Combine
import UserNotifications
import Brudcast
#if canImport(UIKit)
import UIKit
#endif

/// Whether the app may show notifications.
public enum BrudcastPushPermission: String {
    case notDetermined = "not_determined"
    case denied
    case authorized
    case provisional
}

/// What the host wants done with a Brudcast notification that arrives while the app is open.
public enum BrudcastNotificationDecision {
    case show
    case suppress
}

public typealias BrudcastNotificationHandler = (BrudcastPushNotification) -> BrudcastNotificationDecision

/// Decides whether a notification arriving while the app is open shows, answering later, for
/// handlers that cannot answer on the spot, such as one in Dart or JavaScript. Called on the main
/// queue. Call the second argument once, from any queue, within two seconds; after that the
/// notification shows.
public typealias BrudcastAsyncNotificationHandler = (BrudcastPushNotification, @escaping (BrudcastNotificationDecision) -> Void) -> Void

public extension Brudcast {
    /// Push notifications. Add `BrudcastPush.module` to `BrudcastOptions.modules` to run it.
    static var push: BrudcastPush {
        BrudcastPush.shared
    }
}

/// Push notifications: permission, token registration and open tracking.
///
/// Push sends through FCM, so pass the FCM registration token from Firebase Messaging to
/// `setToken`. The SDK does not bundle Firebase.
public final class BrudcastPush: BrudcastModule, BrudcastPushPermissionRequesting {
    public static let shared = BrudcastPush()

    /// The module to list in `BrudcastOptions.modules`.
    public static var module: BrudcastModule {
        shared
    }

    public let name = "push"

    static let eventChannel = "push"
    private static let tokenKey = "brudcast.push.token"
    private static let registeredKey = "brudcast.push.registered"
    private static let permissionKey = "brudcast.push.permission"

    private var context: BrudcastContext?
    private var token: String?
    private var permission: BrudcastPushPermission = .notDetermined
    private let permissionSubject = CurrentValueSubject<BrudcastPushPermission, Never>(.notDetermined)
    private var linkMissing = false
    private var routeMissing = false
    private var registering = false
    private var failures = 0
    private var retry: DispatchWorkItem?
    private var notificationHandler: BrudcastAsyncNotificationHandler?
    private var delegateProxy: NotificationDelegateProxy?

    private init() {}

    /// The last known permission status. Read it on the main queue.
    public var permissionStatus: BrudcastPushPermission {
        permissionSubject.value
    }

    /// Publishes the permission status on the main queue whenever it changes.
    public var permissionPublisher: AnyPublisher<BrudcastPushPermission, Never> {
        permissionSubject.removeDuplicates().receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    public func attach(_ context: BrudcastContext) {
        self.context = context
        token = context.storage.string(Self.tokenKey)
        permission = context.storage.string(Self.permissionKey).flatMap(BrudcastPushPermission.init(rawValue:)) ?? .notDetermined
        permissionSubject.send(permission)
        drainSharedEvents()
        refreshPermission()
    }

    public func sessionDidOpen(_ session: BrudcastSession, payload: [String: Any]) {
        routeMissing = false
        register()
    }

    public func sessionWillReset(_ session: BrudcastSession, completion: @escaping () -> Void) {
        guard let context = context, token != nil, !linkMissing else {
            completion()
            return
        }
        context.request(.delete, "/push-token") { result in
            if case .failure(let error) = result, error.statusCode != 404 {
                BrudcastLogger.shared.info("Could not detach the push token: \(error)")
            }
            context.storage.set(nil, for: Self.registeredKey)
            completion()
        }
    }

    public func appDidBecomeActive() {
        drainSharedEvents()
        refreshPermission()
    }

    /// Stores the FCM registration token and registers it for this user.
    ///
    /// Call it from `messaging(_:didReceiveRegistrationToken:)`. Tokens set before `identify` are
    /// held by the service and attach to the user once a verified session opens.
    ///
    /// - Parameter token: The FCM registration token.
    public func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            BrudcastLogger.shared.error("setToken was given an empty token")
            return
        }
        Brudcast.withContext { _ in
            guard self.token != trimmed else { return }
            self.token = trimmed
            self.context?.storage.set(trimmed, for: Self.tokenKey)
            self.register()
        }
    }

    /// Asks the user for permission to show notifications, then registers with APNs.
    ///
    /// - Parameters:
    ///   - provisional: Ask for provisional authorization, which delivers quietly without a prompt.
    ///   - completion: Called on the main queue with the new status.
    public func requestPermission(provisional: Bool = false, completion: ((BrudcastPushPermission) -> Void)? = nil) {
        var options: UNAuthorizationOptions = [.alert, .sound, .badge]
        if provisional {
            options.insert(.provisional)
        }
        UNUserNotificationCenter.current().requestAuthorization(options: options) { _, error in
            if let error = error {
                BrudcastLogger.shared.warning("Notification permission request failed: \(error.localizedDescription)")
            }
            self.readPermission { status in
                #if canImport(UIKit)
                if status == .authorized || status == .provisional {
                    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                }
                #endif
                DispatchQueue.main.async { completion?(status) }
            }
        }
    }

    public func requestPushPermission(completion: @escaping (Bool) -> Void) {
        requestPermission { status in
            completion(status == .authorized || status == .provisional)
        }
    }

    /// Sets the handler asked when a Brudcast notification arrives while the app is open.
    ///
    /// - Parameter handler: The handler, or nil to show every notification.
    public func setNotificationHandler(_ handler: BrudcastNotificationHandler?) {
        setAsyncNotificationHandler(handler.map { sync in { notification, decide in decide(sync(notification)) } })
    }

    /// Sets a handler that answers later, for bridges whose handler replies asynchronously. Call the
    /// second argument once within two seconds; after that the notification shows. Replaces any
    /// handler set with `setNotificationHandler`. Only `presentationOptions(for:completionHandler:)`
    /// waits for it.
    ///
    /// - Parameter handler: The handler, or nil to show every notification.
    public func setAsyncNotificationHandler(_ handler: BrudcastAsyncNotificationHandler?) {
        DispatchQueue.main.async { self.notificationHandler = handler }
    }

    /// Tells whether a payload came from Brudcast.
    ///
    /// - Parameter userInfo: The notification payload.
    /// - Returns: True when it carries a Brudcast message id.
    public func isBrudcastNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        BrudcastPushNotification(userInfo: userInfo) != nil
    }

    /// Handles the user's response to a notification: records the open and runs its click URL
    /// through the action handler. Call it from
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)` when your app owns the delegate.
    ///
    /// - Parameter response: The response.
    /// - Returns: True when the notification was from Brudcast.
    @discardableResult
    public func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        guard let notification = BrudcastPushNotification(userInfo: response.notification.request.content.userInfo) else {
            return false
        }
        let dismissed = response.actionIdentifier == UNNotificationDismissActionIdentifier
        Brudcast.withContext { context in
            var properties: BrudcastProperties = ["clicked": .bool(!dismissed && notification.clickURL != nil)]
            if let campaignId = notification.campaignId {
                properties["campaignId"] = .string(campaignId)
            }
            context.enqueue(BrudcastEvent(type: dismissed ? "push_dismissed" : "push_opened", messageId: notification.messageId, properties: properties, channel: Self.eventChannel))
            context.flush()
            guard !dismissed, let url = notification.clickURL else { return }
            let scheme = url.scheme?.lowercased()
            let isWeb = scheme == "http" || scheme == "https"
            context.perform(BrudcastAction(kind: isWeb ? .url : .deeplink, value: url.absoluteString, opensInApp: false, source: .push(messageId: notification.messageId)))
        }
        return true
    }

    /// The presentation options for a notification arriving while the app is open. Call it from
    /// `userNotificationCenter(_:willPresent:withCompletionHandler:)` when your app owns the delegate.
    ///
    /// - Parameter notification: The notification.
    /// - Returns: Banner, list and sound unless the notification handler suppresses it; nil when
    ///   the notification is not from Brudcast.
    public func presentationOptions(for notification: UNNotification) -> UNNotificationPresentationOptions? {
        guard let parsed = BrudcastPushNotification(userInfo: notification.request.content.userInfo) else { return nil }
        recordReceived(parsed)
        var decision = BrudcastNotificationDecision.show
        if Thread.isMainThread, let handler = notificationHandler {
            handler(parsed) { decision = $0 }
        }
        return Self.options(for: decision)
    }

    /// The presentation options for a notification arriving while the app is open, waiting for a
    /// handler set with `setAsyncNotificationHandler`. Call it from
    /// `userNotificationCenter(_:willPresent:withCompletionHandler:)` when your app owns the delegate.
    ///
    /// - Parameters:
    ///   - notification: The notification.
    ///   - completionHandler: Called on the main queue with banner, list and sound unless the
    ///     notification handler suppresses it. Not called when the notification is not from Brudcast.
    /// - Returns: False when the notification is not from Brudcast, so the caller presents it itself.
    @discardableResult
    public func presentationOptions(for notification: UNNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) -> Bool {
        guard let parsed = BrudcastPushNotification(userInfo: notification.request.content.userInfo) else { return false }
        recordReceived(parsed)
        DispatchQueue.main.async {
            guard let handler = self.notificationHandler else { return completionHandler(Self.options(for: .show)) }
            let decision = BrudcastDecision(fallback: BrudcastNotificationDecision.show, timeoutMessage: "The notification handler did not answer in time; the notification shows") { decision in
                if Thread.isMainThread {
                    completionHandler(Self.options(for: decision))
                } else {
                    DispatchQueue.main.async { completionHandler(Self.options(for: decision)) }
                }
            }
            handler(parsed, decision.decide)
        }
        return true
    }

    private static func options(for decision: BrudcastNotificationDecision) -> UNNotificationPresentationOptions {
        decision == .show ? [.banner, .list, .sound, .badge] : []
    }

    private func recordReceived(_ notification: BrudcastPushNotification) {
        Brudcast.withContext { context in
            context.enqueue(BrudcastEvent(
                type: "push_received",
                messageId: notification.messageId,
                properties: notification.campaignId.map { ["campaignId": .string($0)] } ?? [:],
                channel: Self.eventChannel,
                id: BrudcastSharedEvents.receivedEventId(messageId: notification.messageId)
            ))
        }
    }

    /// Makes the SDK the notification center's delegate, forwarding everything that is not from
    /// Brudcast to the delegate set before. Call it in `application(_:didFinishLaunchingWithOptions:)`,
    /// after any delegate of your own. Leave it out when your app or another SDK swaps the delegate
    /// later; call `handleNotificationResponse` and `presentationOptions(for:)` instead.
    public func installNotificationDelegate() {
        let center = UNUserNotificationCenter.current()
        if center.delegate is NotificationDelegateProxy { return }
        let proxy = NotificationDelegateProxy(push: self, next: center.delegate)
        delegateProxy = proxy
        center.delegate = proxy
    }

    private func refreshPermission() {
        readPermission { _ in }
    }

    private func readPermission(_ completion: @escaping (BrudcastPushPermission) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: BrudcastPushPermission
            switch settings.authorizationStatus {
            case .authorized: status = .authorized
            case .provisional: status = .provisional
            case .denied: status = .denied
            case .notDetermined: status = .notDetermined
            default: status = .authorized
            }
            Brudcast.withContext { context in
                if status != self.permission {
                    let previous = self.permission
                    self.permission = status
                    context.storage.set(status.rawValue, for: Self.permissionKey)
                    self.permissionSubject.send(status)
                    context.enqueue(BrudcastEvent(type: "push_permission", name: status.rawValue, properties: ["previous": .string(previous.rawValue)], channel: Self.eventChannel))
                    self.register(force: true)
                }
                completion(status)
            }
        }
    }

    private func register(force: Bool = false) {
        guard let context = context, let token = token, let session = context.session else { return }
        guard !linkMissing, !routeMissing, !registering else { return }
        let signature = [token, permission.rawValue, session.userId, session.verified ? "v" : "u"].joined(separator: "|")
        if !force, context.storage.string(Self.registeredKey) == signature {
            return
        }
        registering = true
        retry?.cancel()
        var body: [String: Any] = ["token": token, "provider": "fcm", "permission": permission.rawValue]
        body["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        context.request(.put, "/push-token", body: body) { result in
            self.registering = false
            switch result {
            case .success:
                self.failures = 0
                context.storage.set(signature, for: Self.registeredKey)
                BrudcastLogger.shared.info("Push token registered")
            case .failure(let error):
                if error.statusCode == 409 {
                    self.linkMissing = true
                    BrudcastLogger.shared.error("Push is not linked for this app: link a push application to the in-app application in the dashboard. (\(error.message))")
                } else if error.statusCode == 404 {
                    self.routeMissing = true
                    BrudcastLogger.shared.logOnce(key: "push-route", .warning, "This Brudcast environment does not accept device push tokens yet; register tokens from your backend until it does")
                } else if error.isRetryable {
                    self.failures += 1
                    let delay = min(300, 2 * pow(2, Double(self.failures - 1)))
                    let work = DispatchWorkItem { self.register(force: force) }
                    self.retry = work
                    context.queue.asyncAfter(deadline: .now() + delay, execute: work)
                } else {
                    BrudcastLogger.shared.error("The push token was refused: \(error)")
                }
            }
        }
    }

    private func drainSharedEvents() {
        guard let context = context, let group = context.options.appGroupIdentifier else { return }
        for raw in BrudcastSharedEvents.drain(appGroupIdentifier: group) {
            guard let type = raw["type"] as? String, let messageId = raw["messageId"] as? String else { continue }
            var properties: BrudcastProperties = [:]
            for (key, value) in raw["properties"] as? [String: String] ?? [:] {
                properties[key] = .string(value)
            }
            context.enqueue(BrudcastEvent(
                type: type,
                messageId: messageId,
                properties: properties,
                occurredAt: BrudcastDates.parse(raw["occurredAt"] as? String) ?? Date(),
                channel: Self.eventChannel,
                id: raw["id"] as? String ?? UUID().uuidString.lowercased()
            ))
        }
    }
}

final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate {
    private unowned let push: BrudcastPush
    private weak var next: UNUserNotificationCenterDelegate?

    init(push: BrudcastPush, next: UNUserNotificationCenterDelegate?) {
        self.push = push
        self.next = next
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if push.presentationOptions(for: notification, completionHandler: completionHandler) {
            return
        } else if let next = next, next.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
            next.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        push.handleNotificationResponse(response)
        if let next = next, next.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
            next.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }

    #if os(iOS)
    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        next?.userNotificationCenter?(center, openSettingsFor: notification)
    }
    #endif
}
