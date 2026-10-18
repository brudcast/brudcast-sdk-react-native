import Foundation

/// The session the service issued to this device.
public struct BrudcastSession: Equatable {
    public let token: String
    public let expiresAt: Date
    public let userId: String
    public let externalId: String?
    public let verified: Bool
    public let optedOut: Bool
    public let serverTimeOffset: TimeInterval

    /// The current time on the service's clock, as estimated when the session opened.
    public var serverNow: Date {
        Date().addingTimeInterval(serverTimeOffset)
    }
}

/// A feature module the core runs, such as in-app messaging or push.
///
/// Every method is called on the core's serial queue. A module that touches UI hops to the main
/// queue itself.
public protocol BrudcastModule: AnyObject {
    /// The name sent in the session's `modules` list: `in_app` or `push`.
    var name: String { get }

    /// Called once, when the SDK is initialised.
    func attach(_ context: BrudcastContext)

    /// Called every time a session opens, with the whole session response.
    func sessionDidOpen(_ session: BrudcastSession, payload: [String: Any])

    /// Called before `reset()` drops the user, while the old session still works.
    func sessionWillReset(_ session: BrudcastSession, completion: @escaping () -> Void)

    /// Called after `reset()` dropped the user, before the anonymous session opens.
    func didReset()

    /// Called when the app becomes active and a session is open.
    func appDidBecomeActive()

    /// Called when the app moves to the background.
    func appDidEnterBackground()

    /// Called for every `track` call.
    func didTrack(name: String, properties: BrudcastProperties)

    /// Called for every `screen` call.
    func didScreen(name: String, properties: BrudcastProperties)
}

public extension BrudcastModule {
    func sessionDidOpen(_ session: BrudcastSession, payload: [String: Any]) {}

    func sessionWillReset(_ session: BrudcastSession, completion: @escaping () -> Void) {
        completion()
    }

    func didReset() {}
    func appDidBecomeActive() {}
    func appDidEnterBackground() {}
    func didTrack(name: String, properties: BrudcastProperties) {}
    func didScreen(name: String, properties: BrudcastProperties) {}
}

/// Implemented by the push module so the in-app `request_push_permission` action can reach it.
public protocol BrudcastPushPermissionRequesting: AnyObject {
    /// Asks the user for notification permission.
    ///
    /// - Parameter completion: Called on the main queue with whether notifications are now allowed.
    func requestPushPermission(completion: @escaping (Bool) -> Void)
}

/// What a module can use from the core.
public final class BrudcastContext {
    public let options: BrudcastOptions
    public let storage: BrudcastStorage
    public let api: BrudcastApiClient
    public let queue: DispatchQueue
    public let logger = BrudcastLogger.shared
    public let deviceId: String

    unowned let core: BrudcastCore

    init(core: BrudcastCore, options: BrudcastOptions, storage: BrudcastStorage, api: BrudcastApiClient, queue: DispatchQueue, deviceId: String) {
        self.core = core
        self.options = options
        self.storage = storage
        self.api = api
        self.queue = queue
        self.deviceId = deviceId
    }

    /// The open session, or nil while none is open.
    public var session: BrudcastSession? {
        core.session
    }

    /// True while the app is in the foreground and active.
    public var isAppActive: Bool {
        core.isAppActive
    }

    /// Sends an authenticated request. When no session is open one is opened first, and a 401
    /// reopens the session and retries once. The completion runs on the core queue.
    ///
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - path: The path after `/sdk/v1`.
    ///   - query: Query parameters.
    ///   - body: A JSON body, or nil.
    ///   - completion: Called with the envelope's `data`, or the error.
    public func request(
        _ method: BrudcastHTTPMethod,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        completion: @escaping (Result<[String: Any], BrudcastApiError>) -> Void
    ) {
        core.authorizedRequest(method, path, query: query, body: body, completion: completion)
    }

    /// Queues an event for sending, unless tracking is disabled.
    ///
    /// - Parameter event: The event.
    public func enqueue(_ event: BrudcastEvent) {
        core.enqueue(event)
    }

    /// Sends waiting events now.
    public func flush() {
        core.flush()
    }

    /// Runs an action through the host's action handler, then the default behaviour.
    ///
    /// - Parameter action: The action.
    public func perform(_ action: BrudcastAction) {
        core.perform(action)
    }

    /// Finds another installed module.
    ///
    /// - Parameter type: The module type or a protocol it conforms to.
    /// - Returns: The module, or nil when it is not installed.
    public func module<T>(_ type: T.Type) -> T? {
        core.modules.lazy.compactMap { $0 as? T }.first
    }
}
