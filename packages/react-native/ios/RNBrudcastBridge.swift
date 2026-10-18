import Foundation
import UIKit

/// The Swift side of the core TurboModule: forwards JavaScript calls to the native SDK, and the
/// native SDK's actions to the JavaScript action handler. The Objective-C++ module owns one per
/// JavaScript runtime and calls it on the main queue.
@objc(RNBrudcastBridge)
public final class RNBrudcastBridge: NSObject, RNBrudcastActionRouterTarget {
    private static let router = RNBrudcastActionRouter(
        clock: { ProcessInfo.processInfo.systemUptime },
        schedule: { delay, block in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block) },
        install: { Brudcast.setAsyncActionHandler($0) },
        performDefault: { Brudcast.performDefaultAction($0) }
    )

    /// Sends an action request to JavaScript. The Objective-C++ module sets it to its emitter.
    @objc public var emitActionRequest: ((NSDictionary) -> Void)?

    private var pending: [String: (BrudcastActionResult) -> Void] = [:]

    /// Opens the window in which a launching push tap waits for the JavaScript action handler.
    @objc public func moduleCreated() {
        Self.router.moduleCreated()
    }

    /// Lets go of this runtime when JavaScript reloads or the app tears React Native down: actions
    /// stop going to it, and the ones it never answered get the default.
    @objc public func invalidate() {
        Self.router.clearTarget(self)
        let waiting = pending.values
        pending.removeAll()
        waiting.forEach { $0(.useDefault) }
    }

    /// Starts the SDK. Without an `appGroupIdentifier` in the options, the App Group comes from the
    /// `BrudcastAppGroupIdentifier` Info.plist key the Expo config plugin writes.
    ///
    /// - Parameters:
    ///   - publishableKey: The publishable key.
    ///   - options: The options JavaScript sent, as `NativeOptions` in the spec describes them.
    @objc public func initialize(publishableKey: String, options: NSDictionary) {
        BrudcastSDK.setWrapper(name: "ReactNative", version: options["wrapperVersion"] as? String ?? "unknown")
        Brudcast.initialize(publishableKey: publishableKey, options: Self.options(options))
    }

    @objc public func identify(externalId: String, userHash: String?, traits: NSDictionary?) {
        Brudcast.identify(externalId: externalId, userHash: userHash, traits: traits.map(Self.traits))
    }

    @objc public func reset() {
        Brudcast.reset()
    }

    @objc public func track(name: String, properties: NSDictionary) {
        Brudcast.track(name, properties: Self.properties(properties))
    }

    @objc public func screen(name: String, properties: NSDictionary) {
        Brudcast.screen(name, properties: Self.properties(properties))
    }

    @objc public func setOptedOut(_ optedOut: Bool) {
        optedOut ? Brudcast.optOut() : Brudcast.optIn()
    }

    @objc public func setTrackingEnabled(_ enabled: Bool) {
        enabled ? Brudcast.enableTracking() : Brudcast.disableTracking()
    }

    @objc public func flush() {
        Brudcast.flush()
    }

    @objc public func setActionHandlerEnabled(_ enabled: Bool) {
        enabled ? Self.router.setTarget(self) : Self.router.clearTarget(self)
    }

    /// Answers an action request with the JavaScript handler's result.
    ///
    /// - Parameters:
    ///   - requestId: The request's id.
    ///   - result: `handled` or `useDefault`.
    @objc public func resolveAction(requestId: String, result: String) {
        pending.removeValue(forKey: requestId)?(result == "handled" ? .handled : .useDefault)
    }

    @objc public func deviceId() -> String? {
        Brudcast.deviceId
    }

    func handle(_ action: BrudcastAction, decide: @escaping (BrudcastActionResult) -> Void) {
        guard let emit = emitActionRequest else { return decide(.useDefault) }
        let requestId = UUID().uuidString
        pending[requestId] = decide
        emit(Self.request(action, id: requestId))
    }

    /// Converts properties from JavaScript, which has already limited them to strings, numbers,
    /// booleans and nulls.
    ///
    /// - Parameter raw: The properties.
    /// - Returns: The properties the SDK takes.
    private static func properties(_ raw: NSDictionary) -> BrudcastProperties {
        var properties: BrudcastProperties = [:]
        for case let (key as String, value) in raw {
            properties[key] = BrudcastValue.from(value)
        }
        return properties
    }

    private static func options(_ raw: NSDictionary) -> BrudcastOptions {
        BrudcastOptions(
            environment: environment(raw["environment"] as? NSDictionary),
            logLevel: logLevel(raw["logLevel"] as? String),
            appearance: appearance(raw["appearance"] as? String),
            modules: RNBrudcastModuleRegistry.resolve(raw["modules"] as? [String] ?? []),
            appGroupIdentifier: raw["appGroupIdentifier"] as? String ?? Bundle.main.object(forInfoDictionaryKey: "BrudcastAppGroupIdentifier") as? String,
            accentColor: (raw["accentColor"] as? NSNumber).map { UIColor(argb: $0.uint32Value) }
        )
    }

    private static func environment(_ raw: NSDictionary?) -> BrudcastEnvironment {
        switch raw?["kind"] as? String {
        case "staging": return .staging
        case "uat": return .uat
        case "development": return .development
        case "local": return .local(port: (raw?["port"] as? NSNumber)?.intValue ?? 8191)
        case "custom":
            guard let baseUrl = raw?["baseUrl"] as? String, let url = URL(string: baseUrl) else {
                BrudcastLogger.shared.error("A custom environment needs a base URL; using production")
                return .production
            }
            return .custom(url)
        default: return .production
        }
    }

    private static func logLevel(_ raw: String?) -> BrudcastLogLevel {
        switch raw {
        case "verbose": return .verbose
        case "debug": return .debug
        case "info": return .info
        case "error": return .error
        case "none": return .none
        default: return .warning
        }
    }

    private static func appearance(_ raw: String?) -> BrudcastAppearance {
        switch raw {
        case "light": return .light
        case "dark": return .dark
        default: return .system
        }
    }

    private static func traits(_ raw: NSDictionary) -> BrudcastTraits {
        BrudcastTraits(
            email: raw["email"] as? String,
            phone: raw["phone"] as? String,
            firstName: raw["firstName"] as? String,
            lastName: raw["lastName"] as? String,
            language: raw["language"] as? String,
            timezone: raw["timezone"] as? String
        )
    }

    private static func request(_ action: BrudcastAction, id: String) -> NSDictionary {
        let kind: String
        switch action.kind {
        case .deeplink: kind = "deeplink"
        case .url: kind = "url"
        case .customEvent: kind = "customEvent"
        }
        var request: [String: Any] = [
            "requestId": id,
            "kind": kind,
            "value": action.value,
            "opensInApp": action.opensInApp,
            "verified": action.verified,
        ]
        switch action.source {
        case .inApp(let messageId, let buttonId):
            request["source"] = "inApp"
            request["messageId"] = messageId
            if let buttonId = buttonId {
                request["buttonId"] = buttonId
            }
        case .push(let messageId):
            request["source"] = "push"
            request["messageId"] = messageId
        }
        return request as NSDictionary
    }
}

private extension UIColor {
    convenience init(argb: UInt32) {
        self.init(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
    }
}
