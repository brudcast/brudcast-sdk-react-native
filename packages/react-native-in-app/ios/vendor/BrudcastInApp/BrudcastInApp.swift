import Foundation
import Combine
import Brudcast
#if canImport(UIKit)
import UIKit
#endif

/// What the host's message handler wants done with a message about to show.
public enum BrudcastMessageDecision {
    /// Show it with the standard renderer.
    case show
    /// Do not show it for this trigger.
    case suppress
    /// Do not show it now; the next trigger may show it.
    case `defer`
    /// The host draws it, and reports impression, click and dismiss itself.
    case custom
}

public typealias BrudcastMessageHandler = (BrudcastInAppMessage) -> BrudcastMessageDecision

/// Decides what happens to a message about to show, answering later, for handlers that cannot
/// answer on the spot, such as one in Dart or JavaScript. Called on the main queue. Call the second
/// argument once, from any queue, within two seconds; after that the message shows.
public typealias BrudcastAsyncMessageHandler = (BrudcastInAppMessage, @escaping (BrudcastMessageDecision) -> Void) -> Void

/// Why a message closed without an action.
public enum BrudcastDismissReason: String {
    case closeButton = "close_button"
    case overlayTap = "overlay_tap"
    case swipe
    case back
    case auto
    case host
}

public extension Brudcast {
    /// In-app messaging. Add `BrudcastInApp.module` to `BrudcastOptions.modules` to run it.
    static var inApp: BrudcastInApp {
        BrudcastInApp.shared
    }
}

/// In-app messaging: sync, triggers, display rules, presentation and the inbox.
public final class BrudcastInApp: BrudcastModule {
    public static let shared = BrudcastInApp()

    /// The module to list in `BrudcastOptions.modules`.
    public static var module: BrudcastModule {
        shared
    }

    public let name = "in_app"

    static let eventChannel = "in_app"
    private static let imageTimeout: TimeInterval = 3

    public let inbox = BrudcastInbox()

    private var context: BrudcastContext?
    private var store: MessageStore?
    private var stream: StreamClient?
    private var considered: Set<String> = []
    private var lastUserId: String?
    private var queued: [(id: String, sequence: Int, occurrence: InAppOccurrence)] = []
    private var sequence = 0
    private var presentingId: String?
    private var delayed: (id: String, work: DispatchWorkItem, screen: String?)?
    private var paused = false
    private var currentScreen: String?
    private var syncScheduled = false
    private var messageHandler: BrudcastAsyncMessageHandler?

    private init() {}

    public func attach(_ context: BrudcastContext) {
        self.context = context
        store = MessageStore(storage: context.storage)
        inbox.attach(module: self, context: context)
        stream = StreamClient(
            queue: context.queue,
            onEvent: { [weak self] _ in self?.scheduleSync() },
            onUnauthorized: { [weak self] in self?.sync() }
        )
    }

    public func sessionDidOpen(_ session: BrudcastSession, payload: [String: Any]) {
        if lastUserId != session.userId {
            considered.removeAll()
            queued.removeAll()
            lastUserId = session.userId
        }
        apply(feed: payload, session: session)
        inbox.refreshUnreadCount()
        if context?.isAppActive == true {
            startStream()
            stream?.restart()
        }
    }

    public func didReset() {
        store?.clearUserState()
        considered.removeAll()
        queued.removeAll()
        cancelDelayed()
        inbox.clear()
        stream?.stop()
    }

    public func appDidBecomeActive() {
        sync()
        startStream()
        pump()
    }

    public func appDidEnterBackground() {
        stream?.stop()
        cancelDelayed()
    }

    public func didTrack(name: String, properties: BrudcastProperties) {
        evaluate(.event(name: name, properties: properties))
    }

    public func didScreen(name: String, properties: BrudcastProperties) {
        if let pending = delayed, let screen = pending.screen, screen != name {
            cancelDelayed()
        }
        currentScreen = name
        evaluate(.screen(name: name, properties: properties))
    }

    /// Holds messages back without showing them, such as during checkout or a video. Triggers that
    /// fire meanwhile are kept.
    public func pauseDisplay() {
        guard let context = context else {
            paused = true
            return
        }
        context.queue.async { self.paused = true }
    }

    /// Shows held messages again after `pauseDisplay`.
    public func resumeDisplay() {
        guard let context = context else {
            paused = false
            return
        }
        context.queue.async {
            self.paused = false
            self.pump()
        }
    }

    /// Sets the handler asked before each message shows. Called on the main queue.
    ///
    /// - Parameter handler: The handler, or nil to show every message.
    public func setMessageHandler(_ handler: BrudcastMessageHandler?) {
        setAsyncMessageHandler(handler.map { sync in { message, decide in decide(sync(message)) } })
    }

    /// Sets a handler that answers later, for bridges whose handler replies asynchronously. Call the
    /// second argument once within two seconds; after that the message shows. Replaces any handler
    /// set with `setMessageHandler`.
    ///
    /// - Parameter handler: The handler, or nil to show every message.
    public func setAsyncMessageHandler(_ handler: BrudcastAsyncMessageHandler?) {
        DispatchQueue.main.async { self.messageHandler = handler }
    }

    /// Reports that the host showed a message it draws itself.
    ///
    /// - Parameter messageId: The message id.
    public func reportImpression(messageId: String) {
        context?.queue.async { self.recordImpression(messageId) }
    }

    /// Reports a tap on a button of a message the host draws itself.
    ///
    /// - Parameters:
    ///   - messageId: The message id.
    ///   - buttonId: The design's button id.
    public func reportClick(messageId: String, buttonId: String) {
        context?.queue.async {
            self.context?.enqueue(BrudcastEvent(type: "click", messageId: messageId, buttonId: buttonId, channel: Self.eventChannel))
        }
    }

    /// Reports that a message the host draws itself was closed without an action.
    ///
    /// - Parameter messageId: The message id.
    public func reportDismiss(messageId: String) {
        context?.queue.async {
            self.context?.enqueue(BrudcastEvent(type: "dismiss", messageId: messageId, properties: ["reason": .string(BrudcastDismissReason.host.rawValue)], channel: Self.eventChannel))
        }
    }

    /// Fetches the messages this device should hold now, instead of waiting for the next foreground.
    public func sync() {
        guard let context = context else { return }
        context.queue.async {
            context.request(.get, "/messages") { result in
                switch result {
                case .success(let payload):
                    if let session = context.session {
                        self.apply(feed: payload, session: session)
                    }
                case .failure(let error):
                    BrudcastLogger.shared.info("Sync failed: \(error)")
                }
            }
        }
    }

    private func scheduleSync() {
        guard !syncScheduled, let context = context else { return }
        syncScheduled = true
        context.queue.asyncAfter(deadline: .now() + 0.5) {
            self.syncScheduled = false
            self.sync()
            self.inbox.refreshUnreadCount()
        }
    }

    private func startStream() {
        guard let context = context else { return }
        stream?.start { [weak context] in
            guard let context = context, let session = context.session else { return nil }
            return (context.api.url("/stream"), session.token)
        }
    }

    private func apply(feed payload: [String: Any], session: BrudcastSession) {
        guard let store = store, let context = context else { return }
        let raw = payload["messages"] as? [Any] ?? []
        let change = store.replace(raw: raw, frequencyCap: payload["frequencyCap"], userId: session.userId)
        let removed = Set(change.removed)
        queued.removeAll { removed.contains($0.id) }

        for id in store.markDelivered(store.messages.map(\.id)) {
            context.enqueue(BrudcastEvent(type: "delivered", messageId: id, channel: Self.eventChannel))
        }
        for message in store.messages {
            var reason: String?
            if case .unsupported(let error) = message.designState {
                reason = "\(error)"
            } else if message.triggerUnreadable {
                reason = "unreadable trigger"
            }
            if let reason = reason, store.markUnsupportedReported(message.id) {
                BrudcastLogger.shared.warning("Message \(message.id) needs a newer SDK or has an unreadable design: \(reason)")
                context.enqueue(BrudcastEvent(
                    type: "render_unsupported",
                    messageId: message.id,
                    properties: ["schemaVersion": .number(Double((message.rawDesign["schemaVersion"] as? NSNumber)?.intValue ?? 0)), "sdkVersion": .string(BrudcastSDK.version)],
                    channel: Self.eventChannel
                ))
            }
        }
        evaluate(.session)
    }

    private func evaluate(_ occurrence: InAppOccurrence) {
        guard let store = store, let context = context, let session = context.session else { return }
        let now = session.serverNow
        for message in store.messages {
            guard TriggerMatcher.matches(message.trigger, occurrence) else { continue }
            if occurrence == .session {
                guard considered.insert(message.id).inserted else { continue }
            }
            guard message.id != presentingId,
                  delayed?.id != message.id,
                  !queued.contains(where: { $0.id == message.id }),
                  store.isEligible(message, serverNow: now) else { continue }
            sequence += 1
            queued.append((message.id, sequence, occurrence))
        }
        pump()
    }

    private func pump() {
        guard let store = store, let context = context, let session = context.session else { return }
        guard !paused, context.isAppActive, presentingId == nil, delayed == nil else { return }
        let now = session.serverNow
        queued.removeAll { entry in
            guard let message = store.message(entry.id) else { return true }
            return !store.isEligible(message, serverNow: now)
        }
        guard let next = queued.sorted(by: { lhs, rhs in
            let left = store.message(lhs.id)?.displayRules.priority.rank ?? 0
            let right = store.message(rhs.id)?.displayRules.priority.rank ?? 0
            return left != right ? left > right : lhs.sequence < rhs.sequence
        }).first, let message = store.message(next.id) else { return }
        queued.removeAll { $0.id == next.id }

        let delay = message.displayRules.delaySeconds
        guard delay > 0 else {
            present(message)
            return
        }
        var screen: String?
        if case .screen(let name, _) = next.occurrence {
            screen = name
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.delayed = nil
            if let screen = screen, self.currentScreen != screen { return self.pump() }
            guard let current = self.store?.message(message.id), self.context?.isAppActive == true, !self.paused else { return self.pump() }
            self.present(current)
        }
        delayed = (message.id, work, screen)
        context.queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelDelayed() {
        delayed?.work.cancel()
        delayed = nil
    }

    private func present(_ message: InAppMessage) {
        guard let design = message.design else { return pump() }
        presentingId = message.id
        let publicMessage = message.publicMessage
        DispatchQueue.main.async {
            guard let handler = self.messageHandler else {
                self.context?.queue.async { self.decided(.show, message: message, design: design) }
                return
            }
            let decision = BrudcastDecision(fallback: BrudcastMessageDecision.show, timeoutMessage: "The message handler did not answer in time; message \(message.id) shows") { decision in
                self.context?.queue.async { self.decided(decision, message: message, design: design) }
            }
            handler(publicMessage, decision.decide)
        }
    }

    private func decided(_ decision: BrudcastMessageDecision, message: InAppMessage, design: InAppDesign) {
        switch decision {
        case .show:
            render(message, design: design)
        case .suppress, .defer:
            BrudcastLogger.shared.debug("The host \(decision == .suppress ? "suppressed" : "deferred") message \(message.id)")
            finishPresenting()
        case .custom:
            finishPresenting()
        }
    }

    private func render(_ message: InAppMessage, design: InAppDesign) {
        #if canImport(UIKit)
        guard let context = context else { return }
        InAppImageLoader.shared.prefetch(design.imageURLs, timeout: Self.imageTimeout) { ready in
            context.queue.async {
                guard ready else {
                    BrudcastLogger.shared.info("Images for message \(message.id) were not ready; it waits for the next trigger")
                    return self.finishPresenting()
                }
                DispatchQueue.main.async {
                    InAppPresenter.shared.present(
                        messageId: message.id,
                        design: design,
                        options: context.options,
                        callbacks: self.callbacks(for: message)
                    ) { shown in
                        if !shown {
                            context.queue.async { self.finishPresenting() }
                        }
                    }
                }
            }
        }
        #else
        finishPresenting()
        #endif
    }

    func callbacks(for message: InAppMessage) -> InAppPresentationCallbacks {
        InAppPresentationCallbacks(
            onImpression: { [weak self] in
                self?.context?.queue.async { self?.recordImpression(message.id) }
            },
            onButton: { [weak self] buttonId, action in
                self?.context?.queue.async { self?.handleButton(messageId: message.id, buttonId: buttonId, action: action) }
            },
            onDismiss: { [weak self] reason in
                self?.context?.queue.async {
                    self?.context?.enqueue(BrudcastEvent(type: "dismiss", messageId: message.id, properties: ["reason": .string(reason.rawValue)], channel: Self.eventChannel))
                }
            },
            onClosed: { [weak self] in
                self?.context?.queue.async { self?.finishPresenting() }
            }
        )
    }

    private func recordImpression(_ messageId: String) {
        store?.recordImpression(messageId)
        context?.enqueue(BrudcastEvent(type: "impression", messageId: messageId, channel: Self.eventChannel))
    }

    func handleButton(messageId: String, buttonId: String?, action: InAppAction) {
        guard let context = context else { return }
        if action.type == .dismiss {
            context.enqueue(BrudcastEvent(type: "dismiss", messageId: messageId, buttonId: buttonId, properties: ["reason": .string(BrudcastDismissReason.closeButton.rawValue)], channel: Self.eventChannel))
            return
        }
        context.enqueue(BrudcastEvent(type: "click", messageId: messageId, buttonId: buttonId, channel: Self.eventChannel))
        let source = BrudcastAction.Source.inApp(messageId: messageId, buttonId: buttonId)
        switch action.type {
        case .deeplink:
            context.perform(BrudcastAction(kind: .deeplink, value: action.value ?? "", source: source))
        case .url:
            context.perform(BrudcastAction(kind: .url, value: action.value ?? "", opensInApp: action.opensInApp, source: source))
        case .customEvent:
            let name = action.value ?? ""
            if Brudcast.isValidEventName(name) {
                context.enqueue(BrudcastEvent(type: "custom", name: name, properties: ["messageId": .string(messageId)]))
            }
            context.perform(BrudcastAction(kind: .customEvent, value: name, source: source))
        case .requestPushPermission:
            if let push = context.module(BrudcastPushPermissionRequesting.self) {
                DispatchQueue.main.async {
                    push.requestPushPermission { _ in }
                }
            } else {
                BrudcastLogger.shared.warning("A message asked for push permission, but BrudcastPush.module is not installed")
            }
        case .dismiss:
            break
        }
    }

    private func finishPresenting() {
        presentingId = nil
        pump()
    }

    func inboxMessageOpened(_ message: InAppMessage) {
        store?.markRead(message.id)
    }
}
