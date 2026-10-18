import Foundation

/// Facts about this build of the SDK.
public enum BrudcastSDK {
    public static let version = "0.2.0"

    public static let platform = "ios"

    static var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static let lock = NSLock()
    private static var wrapper: String?

    static var userAgent: String {
        lock.lock()
        defer { lock.unlock() }
        return ["BrudcastSDK-iOS/\(version)", wrapper].compactMap { $0 }.joined(separator: " ")
    }

    /// Names the framework SDK that wraps this one, such as the Flutter plugin, so requests carry it
    /// in their `User-Agent` for support. Call it before `Brudcast.initialize`.
    ///
    /// - Parameters:
    ///   - name: The wrapper's name, such as `Flutter`.
    ///   - version: The wrapper's version.
    public static func setWrapper(name: String, version: String) {
        lock.lock()
        wrapper = "BrudcastSDK-\(name)/\(version)"
        lock.unlock()
    }
}
