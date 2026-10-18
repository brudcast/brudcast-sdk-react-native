import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The Brudcast environment the SDK talks to.
public enum BrudcastEnvironment: Equatable {
    case production
    case staging
    case uat
    case development
    case local(port: Int)
    case custom(URL)

    /// The base URL of the SDK API, ending in `/sdk/v1`.
    public var baseURL: URL {
        switch self {
        case .production:
            return URL(string: "https://in-app-delivery-service.brudcast.com/sdk/v1")!
        case .staging:
            return URL(string: "https://in-app-delivery-service.stg.brudcast.com/sdk/v1")!
        case .uat:
            return URL(string: "https://in-app-delivery-service.uat.brudcast.com/sdk/v1")!
        case .development:
            return URL(string: "https://in-app-delivery-service.dev.brudcast.com/sdk/v1")!
        case .local(let port):
            return URL(string: "http://localhost:\(port)/sdk/v1")!
        case .custom(let url):
            return url
        }
    }
}

/// How much the SDK logs.
public enum BrudcastLogLevel: Int, Comparable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case none = 5

    public static func < (lhs: BrudcastLogLevel, rhs: BrudcastLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Which appearance in-app messages use.
public enum BrudcastAppearance {
    case system
    case light
    case dark
}

/// Optional traits sent with `identify`. Core uses them to fill a new contact; they never overwrite
/// values a contact already has.
public struct BrudcastTraits: Equatable {
    public var email: String?
    public var phone: String?
    public var firstName: String?
    public var lastName: String?
    public var language: String?
    public var timezone: String?

    public init(
        email: String? = nil,
        phone: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        language: String? = nil,
        timezone: String? = nil
    ) {
        self.email = email
        self.phone = phone
        self.firstName = firstName
        self.lastName = lastName
        self.language = language
        self.timezone = timezone
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        object["email"] = email
        object["phone"] = phone
        object["firstName"] = firstName
        object["lastName"] = lastName
        object["language"] = language
        object["timezone"] = timezone
        return object.filter { !(($0.value as? String)?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }
    }

    static func from(json: Any?) -> BrudcastTraits? {
        guard let object = json as? [String: Any] else { return nil }
        return BrudcastTraits(
            email: object["email"] as? String,
            phone: object["phone"] as? String,
            firstName: object["firstName"] as? String,
            lastName: object["lastName"] as? String,
            language: object["language"] as? String,
            timezone: object["timezone"] as? String
        )
    }
}

/// Configuration passed to `Brudcast.initialize`.
public struct BrudcastOptions {
    public var environment: BrudcastEnvironment
    public var logLevel: BrudcastLogLevel
    public var appearance: BrudcastAppearance
    public var modules: [BrudcastModule]
    public var appGroupIdentifier: String?
    #if canImport(UIKit)
    public var accentColor: UIColor?
    #endif

    #if canImport(UIKit)
    /// - Parameters:
    ///   - environment: The environment to talk to.
    ///   - logLevel: The lowest level that is logged.
    ///   - appearance: Light, dark, or following the device.
    ///   - modules: The feature modules to run, such as `BrudcastInApp.module` and `BrudcastPush.module`.
    ///   - appGroupIdentifier: The App Group shared with a notification service extension, so the
    ///     extension can record `push_received` events for the app to send.
    ///   - accentColor: The default colour of primary buttons. The key window's tint is used when nil.
    public init(
        environment: BrudcastEnvironment = .production,
        logLevel: BrudcastLogLevel = .warning,
        appearance: BrudcastAppearance = .system,
        modules: [BrudcastModule] = [],
        appGroupIdentifier: String? = nil,
        accentColor: UIColor? = nil
    ) {
        self.environment = environment
        self.logLevel = logLevel
        self.appearance = appearance
        self.modules = modules
        self.appGroupIdentifier = appGroupIdentifier
        self.accentColor = accentColor
    }
    #else
    /// - Parameters:
    ///   - environment: The environment to talk to.
    ///   - logLevel: The lowest level that is logged.
    ///   - appearance: Light, dark, or following the device.
    ///   - modules: The feature modules to run.
    ///   - appGroupIdentifier: The App Group shared with a notification service extension.
    public init(
        environment: BrudcastEnvironment = .production,
        logLevel: BrudcastLogLevel = .warning,
        appearance: BrudcastAppearance = .system,
        modules: [BrudcastModule] = [],
        appGroupIdentifier: String? = nil
    ) {
        self.environment = environment
        self.logLevel = logLevel
        self.appearance = appearance
        self.modules = modules
        self.appGroupIdentifier = appGroupIdentifier
    }
    #endif
}
