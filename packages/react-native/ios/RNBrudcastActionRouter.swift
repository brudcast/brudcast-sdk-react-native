import Foundation

/// Where actions go once JavaScript has set a handler.
protocol RNBrudcastActionRouterTarget: AnyObject {
    func handle(_ action: BrudcastAction, decide: @escaping (BrudcastActionResult) -> Void)
}

/// Routes actions from in-app buttons and push taps to the JavaScript action handler.
///
/// A push tap that starts the app reaches the SDK before JavaScript has set a handler. For a while
/// after each module is created, actions that arrive with no handler set are held and given to the
/// handler once JavaScript sets one; when the window ends they get the default behaviour. Once the
/// window has ended and no handler is set, no native handler is installed, so the default costs no
/// round trip to JavaScript. Every call happens on the main queue.
final class RNBrudcastActionRouter {
    /// How long after a module is created actions wait for a JavaScript handler.
    static let holdInterval: TimeInterval = 5

    private let clock: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let install: (BrudcastAsyncActionHandler?) -> Void
    private let performDefault: (BrudcastAction) -> Void
    private weak var target: RNBrudcastActionRouterTarget?
    private var holdUntil: TimeInterval = 0
    private var installed = false
    private var held: [BrudcastAction] = []

    /// - Parameters:
    ///   - clock: The current time in seconds.
    ///   - schedule: Runs a block on the main queue after a delay in seconds.
    ///   - install: Installs the native action handler, or removes it with nil.
    ///   - performDefault: Runs an action's default behaviour.
    init(
        clock: @escaping () -> TimeInterval,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
        install: @escaping (BrudcastAsyncActionHandler?) -> Void,
        performDefault: @escaping (BrudcastAction) -> Void
    ) {
        self.clock = clock
        self.schedule = schedule
        self.install = install
        self.performDefault = performDefault
    }

    /// Opens the window in which actions wait for JavaScript, when a module is created.
    func moduleCreated() {
        holdUntil = clock() + Self.holdInterval
        installIfNeeded()
        schedule(Self.holdInterval) { [weak self] in self?.windowEnded() }
    }

    /// Sends actions to a JavaScript handler, starting with the ones held for it.
    ///
    /// - Parameter target: The module whose JavaScript set a handler.
    func setTarget(_ target: RNBrudcastActionRouterTarget) {
        self.target = target
        installIfNeeded()
        let waiting = held
        held.removeAll()
        for action in waiting {
            target.handle(action) { [performDefault] result in
                if result == .useDefault {
                    performDefault(action)
                }
            }
        }
    }

    /// Stops sending actions to a JavaScript handler, when JavaScript clears it or reloads.
    ///
    /// - Parameter target: The module.
    func clearTarget(_ target: RNBrudcastActionRouterTarget) {
        guard self.target === target else { return }
        self.target = nil
        if clock() >= holdUntil {
            uninstall()
        }
    }

    private func route(_ action: BrudcastAction, decide: @escaping (BrudcastActionResult) -> Void) {
        if let target = target {
            target.handle(action, decide: decide)
        } else if clock() < holdUntil {
            held.append(action)
            decide(.handled)
        } else {
            decide(.useDefault)
        }
    }

    private func windowEnded() {
        guard clock() >= holdUntil else { return }
        let expired = held
        held.removeAll()
        expired.forEach(performDefault)
        if target == nil {
            uninstall()
        }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        install { [weak self] action, decide in
            guard let self = self else { return decide(.useDefault) }
            self.route(action, decide: decide)
        }
    }

    private func uninstall() {
        guard installed else { return }
        installed = false
        install(nil)
    }
}
