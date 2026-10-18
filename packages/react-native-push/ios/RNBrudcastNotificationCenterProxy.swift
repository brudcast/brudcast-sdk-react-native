import Foundation
import UIKit
import UserNotifications
import Brudcast

/// Sits in front of whatever `UNUserNotificationCenter` delegate the app already has, such as
/// React Native Firebase's or `expo-notifications`', so taps on Brudcast notifications are recorded
/// with no JavaScript code and Brudcast notifications in the foreground ask the notification
/// handler. Everything is passed on to the delegate it replaced.
///
/// It installs itself when the app finishes launching, then checks again on the next turn of the
/// main queue and whenever the app becomes active, because other libraries set the delegate at
/// launch too. When one of them has replaced it, a new proxy goes in front of that one. A response
/// that reaches more than one proxy is recorded once.
final class RNBrudcastNotificationCenterProxy: NSObject, UNUserNotificationCenterDelegate {
    /// The Info.plist key that turns automatic installation off, for apps that call
    /// `Brudcast.push.handleNotificationResponse` from their own delegate.
    static let automaticKey = "BrudcastAutomaticNotificationDelegate"

    /// Every proxy installed, kept alive here because the notification center holds its delegate
    /// weakly. Touched on the main queue.
    private static var installed: [RNBrudcastNotificationCenterProxy] = []

    /// The responses already passed to the SDK. Touched on the main queue.
    private static var handledResponses: Set<String> = []

    private static var observers: [NSObjectProtocol] = []

    private weak var next: UNUserNotificationCenterDelegate?

    private init(next: UNUserNotificationCenterDelegate?) {
        self.next = next
    }

    /// Installs the proxy now and again whenever another library may have replaced it, unless the
    /// app turned that off in its Info.plist.
    static func installAutomatically() {
        if let automatic = Bundle.main.object(forInfoDictionaryKey: automaticKey) as? Bool, !automatic {
            return
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            install()
            DispatchQueue.main.async { install() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            install()
        })
    }

    /// Puts a proxy in front of the notification center's delegate, unless one already is.
    static func install() {
        let center = UNUserNotificationCenter.current()
        if center.delegate is RNBrudcastNotificationCenterProxy { return }
        let proxy = RNBrudcastNotificationCenterProxy(next: center.delegate)
        installed.append(proxy)
        center.delegate = proxy
    }

    /// Passes a notification response to the SDK once.
    ///
    /// - Parameter response: The response.
    static func record(_ response: UNNotificationResponse) {
        let key = "\(response.notification.request.identifier)|\(response.actionIdentifier)"
        guard Brudcast.push.isBrudcastNotification(response.notification.request.content.userInfo) else { return }
        guard handledResponses.insert(key).inserted else { return }
        Brudcast.push.handleNotificationResponse(response)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Self.record(response)
        if let next = next, next.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
            next.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if Brudcast.push.presentationOptions(for: notification, completionHandler: completionHandler) {
            return
        }
        if let next = next, next.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
            next.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        next?.userNotificationCenter?(center, openSettingsFor: notification)
    }
}
