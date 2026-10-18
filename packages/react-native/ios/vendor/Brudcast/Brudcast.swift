import Foundation

/// The Brudcast SDK.
///
/// Call `initialize` once at launch. Every other call may come before it; calls made earlier are
/// held and run once the SDK starts. No call throws or blocks the main thread.
public enum Brudcast {
    private static let lock = NSLock()
    private static var core: BrudcastCore?
    private static var pending: [(BrudcastCore) -> Void] = []
    private static var pendingActionHandler: BrudcastAsyncActionHandler?

    /// Starts the SDK.
    ///
    /// - Parameters:
    ///   - publishableKey: The application's publishable key (`bpk_...`) from the dashboard. It is
    ///     public by design; never ship the identity secret in the app.
    ///   - options: Environment, logging, appearance and the modules to run.
    public static func initialize(publishableKey: String, options: BrudcastOptions = BrudcastOptions()) {
        BrudcastLogger.shared.setLevel(options.logLevel)
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            BrudcastLogger.shared.error("initialize needs a publishable key")
            assertionFailure("Brudcast.initialize needs a publishable key")
            return
        }
        lock.lock()
        guard core == nil else {
            lock.unlock()
            BrudcastLogger.shared.warning("initialize was called more than once; the first call wins")
            return
        }
        let created = BrudcastCore(publishableKey: key, options: options, storage: .standard())
        created.actionHandler = pendingActionHandler
        core = created
        let replay = pending
        pending.removeAll()
        lock.unlock()

        created.start()
        replay.forEach { $0(created) }
    }

    /// True once `initialize` has run.
    public static var isInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return core != nil
    }

    /// This install's device id, a random UUID kept in the Keychain. Nil before `initialize`.
    public static var deviceId: String? {
        lock.lock()
        defer { lock.unlock() }
        return core?.deviceId
    }

    /// Identifies the signed-in user.
    ///
    /// - Parameters:
    ///   - externalId: Your id for the user, at most 191 characters.
    ///   - userHash: `HMAC-SHA256(identitySecret, externalId)` in hex, computed on your server. Required
    ///     when the application enforces identity verification.
    ///   - traits: Details used when Brudcast creates the contact.
    public static func identify(externalId: String, userHash: String?, traits: BrudcastTraits? = nil) {
        run { $0.identify(externalId: externalId, userHash: userHash, traits: traits) }
    }

    /// Forgets the user on logout. The device keeps its id, and its push token stops reaching the
    /// previous user.
    public static func reset() {
        run { $0.reset() }
    }

    /// Records a custom event. In-app messages triggered by the event show at once.
    ///
    /// - Parameters:
    ///   - name: The event name: a letter, then up to 63 letters, digits and `_ . : -`.
    ///   - properties: Event properties.
    public static func track(_ name: String, properties: BrudcastProperties = [:]) {
        run { $0.track(name, properties: properties) }
    }

    /// Records that the user is on a screen. In-app messages triggered by the screen show at once.
    ///
    /// - Parameters:
    ///   - name: The screen name.
    ///   - properties: Screen properties.
    public static func screen(_ name: String, properties: BrudcastProperties = [:]) {
        run { $0.screen(name, properties: properties) }
    }

    /// Stops in-app campaign messages for this user. Transactional messages still arrive.
    public static func optOut() {
        run { $0.setOptedOut(true) }
    }

    /// Resumes in-app campaign messages for this user.
    public static func optIn() {
        run { $0.setOptedOut(false) }
    }

    /// Stops collecting and sending events, for consent frameworks. Waiting events are discarded.
    public static func disableTracking() {
        run { $0.setTrackingEnabled(false) }
    }

    /// Resumes collecting events after `disableTracking`.
    public static func enableTracking() {
        run { $0.setTrackingEnabled(true) }
    }

    /// Sends waiting events now instead of on the next timer tick.
    public static func flush() {
        run { core in core.queue.async { core.flush() } }
    }

    /// Sets the handler for deep links, URLs and custom events from in-app buttons and push taps.
    /// Return `.handled` to skip the default behaviour. Called on the main queue.
    ///
    /// - Parameter handler: The handler, or nil to restore the defaults.
    public static func setActionHandler(_ handler: BrudcastActionHandler?) {
        setAsyncActionHandler(handler.map { sync in { action, decide in decide(sync(action)) } })
    }

    /// Sets a handler that answers later, for bridges whose handler replies asynchronously. Call the
    /// second argument once within two seconds; after that the default behaviour runs. Replaces any
    /// handler set with `setActionHandler`.
    ///
    /// - Parameter handler: The handler, or nil to restore the defaults.
    public static func setAsyncActionHandler(_ handler: BrudcastAsyncActionHandler?) {
        lock.lock()
        if let core = core {
            lock.unlock()
            DispatchQueue.main.async { core.actionHandler = handler }
        } else {
            pendingActionHandler = handler
            lock.unlock()
        }
    }

    /// Runs the default behaviour for an action, skipping the action handler: opens the link, or does
    /// nothing for a custom event. For bridges that held an action and later chose the default.
    ///
    /// - Parameter action: The action.
    public static func performDefaultAction(_ action: BrudcastAction) {
        DispatchQueue.main.async { DefaultActionPerformer.perform(action) }
    }

    /// Checks an event name against the rule the service applies.
    ///
    /// - Parameter name: The name.
    /// - Returns: True for a letter followed by up to 63 letters, digits and `_ . : -`.
    public static func isValidEventName(_ name: String) -> Bool {
        BrudcastCore.isValidEventName(name)
    }

    /// The running core's module context, for modules that need it outside their callbacks.
    ///
    /// - Parameter body: Called with the context once the SDK is initialised.
    public static func withContext(_ body: @escaping (BrudcastContext) -> Void) {
        run { core in core.queue.async { body(core.context) } }
    }

    private static func run(_ call: @escaping (BrudcastCore) -> Void) {
        lock.lock()
        if let core = core {
            lock.unlock()
            call(core)
        } else {
            pending.append(call)
            lock.unlock()
        }
    }
}
