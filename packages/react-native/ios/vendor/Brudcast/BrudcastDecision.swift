import Foundation

/// Collects one answer from a handler that answers later, such as one written in Dart or JavaScript
/// that replies over a bridge. The first of the handler's answer and the timeout's fallback wins,
/// and every later answer is ignored. For modules.
public final class BrudcastDecision<Value> {
    /// How long the SDK waits for a host handler before it uses the default.
    public static var handlerTimeout: TimeInterval { 2 }

    private let lock = NSLock()
    private var decided = false
    private let fallback: Value
    private let onDecided: (Value) -> Void

    /// - Parameters:
    ///   - fallback: The answer used when the handler does not answer in time.
    ///   - timeout: How long to wait for the handler.
    ///   - timeoutMessage: The warning logged when the fallback is used.
    ///   - onDecided: Called once with the answer: on the queue that answered, or on the main queue
    ///     for the fallback.
    public init(fallback: Value, timeout: TimeInterval = 2, timeoutMessage: String, onDecided: @escaping (Value) -> Void) {
        self.fallback = fallback
        self.onDecided = onDecided
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [self] in
            guard claim() else { return }
            BrudcastLogger.shared.warning(timeoutMessage)
            onDecided(fallback)
        }
    }

    /// Records the handler's answer, unless one was already recorded or the timeout passed.
    ///
    /// - Parameter value: The answer.
    public func decide(_ value: Value) {
        guard claim() else { return }
        onDecided(value)
    }

    private func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !decided else { return false }
        decided = true
        return true
    }
}
