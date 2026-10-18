import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct BrudcastIdentity: Equatable {
    var externalId: String
    var userHash: String?
    var traits: BrudcastTraits?
}

/// The SDK's state machine. Everything mutable is touched only on `queue`.
final class BrudcastCore {
    static let eventNamePattern = try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9_.:-]{0,63}$")

    private static let trackingDisabledKey = "brudcast.tracking_disabled"
    private static let flushInterval: TimeInterval = 10
    private static let refreshLeeway: TimeInterval = 60
    private static let maxSessionBackoff: TimeInterval = 300
    private static let persistDelay: TimeInterval = 1
    private static let invalidBatchStatuses: Set<Int> = [400, 413, 422]

    let queue: DispatchQueue
    let options: BrudcastOptions
    let storage: BrudcastStorage
    let api: BrudcastApiClient
    let deviceId: String
    let modules: [BrudcastModule]
    private(set) var context: BrudcastContext!

    private(set) var session: BrudcastSession?
    private(set) var isAppActive = false
    private var identity: BrudcastIdentity?
    private var eventOwner: String?
    private var retiredSessions: [String: BrudcastSession] = [:]
    private var persistScheduled = false
    private var identityRejected = false
    private var keyRejected = false
    private var trackingDisabled: Bool
    private var opening = false
    private var openWaiters: [(Result<BrudcastSession, BrudcastApiError>) -> Void] = []
    private var sessionFailures = 0
    private var sessionRetry: DispatchWorkItem?
    private var refreshTimer: DispatchWorkItem?
    private var flushTimer: DispatchSourceTimer?
    private var flushing = false
    private var flushWaiters: [() -> Void] = []
    private let events: EventQueue
    var actionHandler: BrudcastAsyncActionHandler?
    private var observers: [NSObjectProtocol] = []

    init(publishableKey: String, options: BrudcastOptions, storage: BrudcastStorage, session urlSession: URLSession = .shared) {
        self.queue = DispatchQueue(label: "com.brudcast.sdk.core")
        self.options = options
        self.storage = storage
        self.api = BrudcastApiClient(baseURL: options.environment.baseURL, publishableKey: publishableKey, session: urlSession)
        self.deviceId = DeviceIdentifier.load(storage: storage)
        self.modules = options.modules
        self.events = EventQueue(storage: storage)
        self.trackingDisabled = storage.bool(Self.trackingDisabledKey)
        self.identity = Self.loadIdentity(storage: storage)
        self.eventOwner = identity?.externalId
        self.context = BrudcastContext(core: self, options: options, storage: storage, api: api, queue: queue, deviceId: deviceId)
    }

    func start() {
        queue.async {
            for module in self.modules {
                module.attach(self.context)
            }
            self.openSession { _ in }
        }
        observeLifecycle()
    }

    func identify(externalId: String, userHash: String?, traits: BrudcastTraits?) {
        let trimmed = externalId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 191 else {
            BrudcastLogger.shared.error("identify needs an external id of 1 to 191 characters")
            return
        }
        if let hash = userHash, hash.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) == nil {
            BrudcastLogger.shared.error("identify was given a user hash that is not a hex HMAC-SHA256; compute it on your server")
            return
        }
        queue.async {
            let next = BrudcastIdentity(externalId: trimmed, userHash: userHash, traits: traits)
            if next == self.identity, self.session?.externalId == trimmed, !self.identityRejected {
                return
            }
            let userChanged = self.identity?.externalId != trimmed
            self.eventOwner = trimmed
            self.flushThen {
                self.identity = next
                self.identityRejected = false
                self.persistIdentity()
                if userChanged {
                    self.retire(self.session)
                    self.session = nil
                }
                self.reopenSession()
            }
        }
    }

    func reset() {
        queue.async {
            let previous = self.session
            self.eventOwner = nil
            self.flushThen {
                let finish = {
                    self.identity = nil
                    self.identityRejected = false
                    self.persistIdentity()
                    self.retire(self.session ?? previous)
                    self.session = nil
                    for module in self.modules {
                        module.didReset()
                    }
                    self.reopenSession()
                }
                guard let previous = previous else {
                    finish()
                    return
                }
                let group = DispatchGroup()
                for module in self.modules {
                    group.enter()
                    module.sessionWillReset(previous) {
                        group.leave()
                    }
                }
                group.notify(queue: self.queue, execute: finish)
            }
        }
    }

    func track(_ name: String, properties: BrudcastProperties) {
        guard Self.isValidEventName(name) else {
            BrudcastLogger.shared.error("track ignored \"\(name)\": names start with a letter and use at most 64 letters, digits and _ . : -")
            return
        }
        let properties = properties.droppingNonFiniteNumbers()
        queue.async {
            self.enqueue(BrudcastEvent(type: "custom", name: name, properties: properties))
            for module in self.modules {
                module.didTrack(name: name, properties: properties)
            }
        }
    }

    func screen(_ name: String, properties: BrudcastProperties) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else {
            BrudcastLogger.shared.error("screen needs a name of 1 to 64 characters")
            return
        }
        let properties = properties.droppingNonFiniteNumbers()
        queue.async {
            self.enqueue(BrudcastEvent(type: "screen", name: trimmed, properties: properties))
            for module in self.modules {
                module.didScreen(name: trimmed, properties: properties)
            }
        }
    }

    func setTrackingEnabled(_ enabled: Bool) {
        queue.async {
            self.trackingDisabled = !enabled
            self.storage.set(!enabled, for: Self.trackingDisabledKey)
            if !enabled {
                self.events.clear()
            }
        }
    }

    func setOptedOut(_ optedOut: Bool) {
        queue.async {
            self.authorizedRequest(.post, optedOut ? "/opt-out" : "/opt-in") { result in
                if case .failure(let error) = result {
                    BrudcastLogger.shared.warning("Could not change the opt-out choice: \(error)")
                }
            }
        }
    }

    static func isValidEventName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..., in: name)
        return eventNamePattern.firstMatch(in: name, range: range) != nil
    }

    private func reopenSession() {
        sessionRetry?.cancel()
        sessionFailures = 0
        openSession { _ in }
    }

    func openSession(_ completion: @escaping (Result<BrudcastSession, BrudcastApiError>) -> Void) {
        openWaiters.append(completion)
        guard !opening else { return }
        if keyRejected {
            resolveWaiters(.failure(BrudcastApiError(statusCode: 401, code: "key_rejected", message: "The publishable key was refused")))
            return
        }
        if identityRejected {
            resolveWaiters(.failure(BrudcastApiError(statusCode: 401, code: "identity_rejected", message: "The user hash was refused")))
            return
        }
        opening = true
        sessionRetry?.cancel()

        var body: [String: Any] = [
            "deviceId": deviceId,
            "platform": BrudcastSDK.platform,
            "sdkVersion": BrudcastSDK.version,
            "modules": modules.map(\.name),
        ]
        body["appVersion"] = BrudcastSDK.appVersion
        if let identity = identity {
            body["externalId"] = identity.externalId
            body["userHash"] = identity.userHash
            if let traits = identity.traits?.jsonObject, !traits.isEmpty {
                body["traits"] = traits
            }
        }
        let requestedIdentity = identity

        api.send(.post, "/sessions", body: body) { result in
            self.queue.async {
                self.opening = false
                switch result {
                case .success(let payload):
                    guard let session = Self.parseSession(payload) else {
                        BrudcastLogger.shared.error("The session response could not be read")
                        self.scheduleSessionRetry()
                        self.resolveWaiters(.failure(BrudcastApiError(statusCode: nil, code: "decoding", message: "Unreadable session")))
                        return
                    }
                    guard requestedIdentity == self.identity else {
                        self.openSession { _ in }
                        return
                    }
                    self.sessionFailures = 0
                    self.session = session
                    self.scheduleRefresh(session)
                    BrudcastLogger.shared.info("Session open for \(session.externalId ?? "an anonymous user")\(session.verified ? " (verified)" : "")")
                    for module in self.modules {
                        module.sessionDidOpen(session, payload: payload)
                    }
                    self.resolveWaiters(.success(session))
                    self.flush()
                case .failure(let error):
                    self.handleSessionFailure(error, hadIdentity: requestedIdentity != nil)
                    self.resolveWaiters(.failure(error))
                }
            }
        }
    }

    private func handleSessionFailure(_ error: BrudcastApiError, hadIdentity: Bool) {
        if error.statusCode == 401 {
            if !Self.isKeyRejection(error, hadIdentity: hadIdentity) {
                identityRejected = true
                BrudcastLogger.shared.error("The service refused this user's identity: \(error.message). Compute userHash on your server as HMAC-SHA256(identitySecret, externalId), and call identify again.")
            } else {
                keyRejected = true
                BrudcastLogger.shared.error("The service refused the publishable key: \(error.message)")
            }
            return
        }
        if error.isRetryable {
            BrudcastLogger.shared.info("Could not open a session, retrying: \(error)")
            scheduleSessionRetry()
        } else {
            BrudcastLogger.shared.error("Could not open a session: \(error)")
        }
    }

    /// Tells a refused publishable key apart from a refused user hash on a 401 from `/sessions`.
    ///
    /// The service's `code` decides when it sends one. Otherwise a request without an identity can
    /// only have failed on its key, and one with an identity failed on its key only when the
    /// message names the key.
    ///
    /// - Parameters:
    ///   - error: The 401.
    ///   - hadIdentity: Whether the request carried an external id.
    /// - Returns: True when the key was refused.
    static func isKeyRejection(_ error: BrudcastApiError, hadIdentity: Bool) -> Bool {
        switch error.code {
        case "key_rejected":
            return true
        case "identity_rejected":
            return false
        default:
            return !hadIdentity || error.message.lowercased().contains("publishable key")
        }
    }

    private func resolveWaiters(_ result: Result<BrudcastSession, BrudcastApiError>) {
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters {
            waiter(result)
        }
    }

    private func scheduleSessionRetry() {
        sessionFailures += 1
        let delay = min(Self.maxSessionBackoff, 2 * pow(2, Double(sessionFailures - 1)))
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.session == nil || self.isExpiring(self.session) else { return }
            self.openSession { _ in }
        }
        sessionRetry = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleRefresh(_ session: BrudcastSession) {
        refreshTimer?.cancel()
        let delay = max(5, session.expiresAt.timeIntervalSinceNow - Self.refreshLeeway)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.session == session else { return }
            self.openSession { _ in }
        }
        refreshTimer = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func isExpiring(_ session: BrudcastSession?) -> Bool {
        guard let session = session else { return true }
        return session.expiresAt.timeIntervalSinceNow < Self.refreshLeeway / 2
    }

    private func withSession(_ completion: @escaping (Result<BrudcastSession, BrudcastApiError>) -> Void) {
        if let session = session, !isExpiring(session) {
            completion(.success(session))
            return
        }
        openSession(completion)
    }

    func authorizedRequest(
        _ method: BrudcastHTTPMethod,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        retried: Bool = false,
        completion: @escaping (Result<[String: Any], BrudcastApiError>) -> Void
    ) {
        withSession { sessionResult in
            switch sessionResult {
            case .failure(let error):
                completion(.failure(error))
            case .success(let session):
                self.api.send(method, path, query: query, body: body, token: session.token) { result in
                    self.queue.async {
                        if case .failure(let error) = result, error.statusCode == 401, !retried {
                            if self.session == session {
                                self.session = nil
                            }
                            self.authorizedRequest(method, path, query: query, body: body, retried: true, completion: completion)
                            return
                        }
                        completion(result)
                    }
                }
            }
        }
    }

    static func parseSession(_ payload: [String: Any]) -> BrudcastSession? {
        guard let sessionObject = payload["session"] as? [String: Any],
              let token = sessionObject["token"] as? String,
              let expiresAt = BrudcastDates.parse(sessionObject["expiresAt"] as? String),
              let user = payload["user"] as? [String: Any],
              let userId = user["id"] as? String else {
            return nil
        }
        let serverTime = BrudcastDates.parse(payload["serverTime"] as? String)
        return BrudcastSession(
            token: token,
            expiresAt: expiresAt,
            userId: userId,
            externalId: user["externalId"] as? String,
            verified: user["verified"] as? Bool ?? false,
            optedOut: user["optedOut"] as? Bool ?? false,
            serverTimeOffset: serverTime.map { $0.timeIntervalSinceNow } ?? 0
        )
    }

    func enqueue(_ event: BrudcastEvent) {
        guard !trackingDisabled else { return }
        var owned = event
        owned.owner = eventOwner
        let flushNow = events.enqueue(owned)
        schedulePersist()
        if flushNow {
            flush()
        }
    }

    /// Sends the next batch with the session of the user who queued it.
    ///
    /// Anonymous events go with whoever is signed in now, since an anonymous device that signs in is
    /// the same person. Events of a user whose session is still opening wait for it. Events of a
    /// user who has since signed out go with that user's last session while it lasts, and are
    /// dropped after that rather than credited to someone else.
    func flush() {
        guard !flushing else { return }
        guard let batch = events.nextBatch(), let first = batch.first else {
            drainFlushWaiters()
            return
        }
        let body: [String: Any] = ["events": batch.map(\.apiObject)]
        guard let owner = first.owner, owner != identity?.externalId else {
            flushing = true
            authorizedRequest(.post, "/events", body: body) { result in
                self.finishFlush(batch, result: result, retiredOwner: nil)
            }
            return
        }
        if owner == eventOwner {
            events.complete(batch, outcome: .unauthorized)
            drainFlushWaiters()
            return
        }
        guard let retired = retiredSessions[owner], !isExpiring(retired) else {
            retiredSessions[owner] = nil
            BrudcastLogger.shared.warning("\(batch.count) events of a signed-out user outlived their session")
            events.complete(batch, outcome: .discarded)
            flush()
            return
        }
        flushing = true
        api.send(.post, "/events", body: body, token: retired.token) { result in
            self.queue.async {
                self.finishFlush(batch, result: result, retiredOwner: owner)
            }
        }
    }

    private func finishFlush(_ batch: [BrudcastEvent], result: Result<[String: Any], BrudcastApiError>, retiredOwner: String?) {
        flushing = false
        switch result {
        case .success:
            events.complete(batch, outcome: .sent)
            flush()
        case .failure(let error) where error.statusCode == 401 && retiredOwner != nil:
            retiredSessions[retiredOwner!] = nil
            events.complete(batch, outcome: .discarded)
            flush()
        case .failure(let error) where error.statusCode == 401 || error.code == "key_rejected" || error.code == "identity_rejected":
            events.complete(batch, outcome: .unauthorized)
            drainFlushWaiters()
        case .failure(let error) where error.isRetryable:
            events.complete(batch, outcome: .retry)
            drainFlushWaiters()
        case .failure(let error):
            BrudcastLogger.shared.warning("Events rejected: \(error)")
            let invalid = error.statusCode.map(Self.invalidBatchStatuses.contains) ?? false
            events.complete(batch, outcome: invalid ? .rejected : .discarded)
            flush()
        }
    }

    private func retire(_ session: BrudcastSession?) {
        retiredSessions = retiredSessions.filter { !isExpiring($0.value) }
        guard let session = session, let externalId = session.externalId, !isExpiring(session) else { return }
        retiredSessions[externalId] = session
    }

    private func schedulePersist() {
        guard !persistScheduled else { return }
        persistScheduled = true
        queue.asyncAfter(deadline: .now() + Self.persistDelay) {
            self.persistScheduled = false
            self.events.persistIfNeeded()
        }
    }

    private func flushThen(timeout: TimeInterval = 5, _ next: @escaping () -> Void) {
        var done = false
        let finish = {
            guard !done else { return }
            done = true
            next()
        }
        flushWaiters.append(finish)
        queue.asyncAfter(deadline: .now() + timeout, execute: finish)
        if session == nil {
            drainFlushWaiters()
        } else {
            flush()
        }
    }

    private func drainFlushWaiters() {
        let waiters = flushWaiters
        flushWaiters.removeAll()
        waiters.forEach { $0() }
    }

    private func startFlushTimer() {
        guard flushTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        timer.resume()
        flushTimer = timer
    }

    private func stopFlushTimer() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    func perform(_ action: BrudcastAction) {
        DispatchQueue.main.async {
            guard let handler = self.actionHandler else { return DefaultActionPerformer.perform(action) }
            let decision = BrudcastDecision(fallback: BrudcastActionResult.useDefault, timeoutMessage: "The action handler did not answer in time; the default behaviour runs") { result in
                guard result == .useDefault else { return }
                if Thread.isMainThread {
                    DefaultActionPerformer.perform(action)
                } else {
                    DispatchQueue.main.async { DefaultActionPerformer.perform(action) }
                }
            }
            handler(action, decision.decide)
        }
    }

    private func observeLifecycle() {
        #if canImport(UIKit)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.appDidBecomeActive() }
        })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.isAppActive = false }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.appDidEnterBackground()
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.sync { self?.events.persistIfNeeded() }
        })
        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .active {
                self.queue.async { self.appDidBecomeActive() }
            }
        }
        #else
        queue.async { self.appDidBecomeActive() }
        #endif
    }

    private func appDidBecomeActive() {
        guard !isAppActive else { return }
        isAppActive = true
        keyRejected = false
        startFlushTimer()
        if session == nil || isExpiring(session) {
            openSession { _ in }
        } else {
            for module in modules {
                module.appDidBecomeActive()
            }
        }
        flush()
    }

    private func appDidEnterBackground() {
        #if canImport(UIKit)
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Brudcast flush") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        queue.async {
            self.isAppActive = false
            self.events.persistIfNeeded()
            self.stopFlushTimer()
            for module in self.modules {
                module.appDidEnterBackground()
            }
            self.flushThen(timeout: 20) {
                DispatchQueue.main.async {
                    if task != .invalid {
                        UIApplication.shared.endBackgroundTask(task)
                        task = .invalid
                    }
                }
            }
        }
        #endif
    }

    private static func loadIdentity(storage: BrudcastStorage) -> BrudcastIdentity? {
        guard let object = storage.readJSON("identity.json") as? [String: Any],
              let externalId = object["externalId"] as? String else {
            return nil
        }
        return BrudcastIdentity(
            externalId: externalId,
            userHash: object["userHash"] as? String,
            traits: BrudcastTraits.from(json: object["traits"])
        )
    }

    private func persistIdentity() {
        guard let identity = identity else {
            storage.remove("identity.json")
            return
        }
        var object: [String: Any] = ["externalId": identity.externalId]
        object["userHash"] = identity.userHash
        if let traits = identity.traits?.jsonObject {
            object["traits"] = traits
        }
        storage.writeJSON(object, to: "identity.json")
    }
}
