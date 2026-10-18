import Foundation
#if canImport(UIKit)
import UIKit
import SafariServices
#endif

/// Something a message asked the app to do: open a deep link or a URL, or handle a custom event.
public struct BrudcastAction: Equatable {
    public enum Kind: String {
        case deeplink
        case url
        case customEvent = "custom_event"
    }

    public enum Source: Equatable {
        case inApp(messageId: String, buttonId: String?)
        case push(messageId: String)
    }

    public let kind: Kind
    public let value: String
    public let opensInApp: Bool
    public let source: Source
    /// False when the action came from input another app could forge. Every action the SDK creates
    /// today comes from the app's own UI or from the system notification center, so it is true.
    /// Matches `BrudcastAction.verified` on Android, where a push tap can be forged.
    public let verified: Bool

    public init(kind: Kind, value: String, opensInApp: Bool = false, source: Source, verified: Bool = true) {
        self.kind = kind
        self.value = value
        self.opensInApp = opensInApp
        self.source = source
        self.verified = verified
    }
}

/// What the host's action handler did with an action.
public enum BrudcastActionResult {
    case handled
    case useDefault
}

public typealias BrudcastActionHandler = (BrudcastAction) -> BrudcastActionResult

/// Decides what to do with an action, answering later, for handlers that cannot answer on the spot,
/// such as one in Dart or JavaScript. Called on the main queue. Call the second argument once, from
/// any queue, within two seconds; after that the default behaviour runs.
public typealias BrudcastAsyncActionHandler = (BrudcastAction, @escaping (BrudcastActionResult) -> Void) -> Void

enum DefaultActionPerformer {
    static func perform(_ action: BrudcastAction) {
        #if canImport(UIKit)
        guard action.kind != .customEvent else { return }
        guard let url = URL(string: action.value) else {
            BrudcastLogger.shared.warning("Ignoring an action with an invalid URL: \(action.value)")
            return
        }
        let scheme = url.scheme?.lowercased()
        let isWeb = scheme == "http" || scheme == "https"
        if action.kind == .url, action.opensInApp, isWeb, let presenter = BrudcastPresentation.topViewController() {
            let safari = SFSafariViewController(url: url)
            presenter.present(safari, animated: true)
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                BrudcastLogger.shared.warning("No app could open \(url.absoluteString)")
            }
        }
        #endif
    }
}

#if canImport(UIKit)
/// Finds where the SDK can present UI.
public enum BrudcastPresentation {
    /// The foreground active window scene, if there is one.
    public static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// The app's own key window in the active scene, ignoring windows above it such as a message.
    public static func keyWindow() -> UIWindow? {
        let windows = activeScene()?.windows ?? []
        return windows.first { $0.isKeyWindow && $0.windowLevel == .normal }
            ?? windows.first { $0.windowLevel == .normal && !$0.isHidden }
            ?? windows.first
    }

    /// The topmost presented view controller of the app's key window.
    public static func topViewController() -> UIViewController? {
        var top = keyWindow()?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
