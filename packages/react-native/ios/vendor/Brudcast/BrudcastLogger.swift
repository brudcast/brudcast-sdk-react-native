import Foundation
import os

/// The SDK's logger. Modules log through it so one level controls everything.
public final class BrudcastLogger {
    public static let shared = BrudcastLogger()

    private let log = OSLog(subsystem: "com.brudcast.sdk", category: "Brudcast")
    private let lock = NSLock()
    private var level: BrudcastLogLevel = .warning
    private var onceKeys: Set<String> = []

    var currentLevel: BrudcastLogLevel {
        lock.lock()
        defer { lock.unlock() }
        return level
    }

    func setLevel(_ newLevel: BrudcastLogLevel) {
        lock.lock()
        level = newLevel
        lock.unlock()
    }

    /// Logs a message at the given level.
    ///
    /// - Parameters:
    ///   - level: The message's level.
    ///   - message: The message, built only when the level is enabled.
    public func log(_ level: BrudcastLogLevel, _ message: @autoclosure () -> String) {
        guard level != .none, level >= currentLevel else { return }
        let type: OSLogType
        switch level {
        case .verbose, .debug:
            type = .debug
        case .info:
            type = .info
        case .warning:
            type = .default
        case .error, .none:
            type = .error
        }
        os_log("%{public}@", log: log, type: type, "[Brudcast] \(message())")
    }

    /// Logs a message the first time a key is seen, and never again in this process.
    ///
    /// - Parameters:
    ///   - key: What makes the message unique.
    ///   - level: The message's level.
    ///   - message: The message.
    public func logOnce(key: String, _ level: BrudcastLogLevel, _ message: @autoclosure () -> String) {
        lock.lock()
        let isNew = onceKeys.insert(key).inserted
        lock.unlock()
        if isNew {
            log(level, message())
        }
    }

    public func verbose(_ message: @autoclosure () -> String) { log(.verbose, message()) }
    public func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    public func info(_ message: @autoclosure () -> String) { log(.info, message()) }
    public func warning(_ message: @autoclosure () -> String) { log(.warning, message()) }
    public func error(_ message: @autoclosure () -> String) { log(.error, message()) }
}
