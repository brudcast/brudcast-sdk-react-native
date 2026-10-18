import Foundation
import Combine
import UIKit
import Brudcast

/// The Swift side of the in-app TurboModule: registers the native in-app module, forwards
/// JavaScript calls to it, and routes the message handler and the unread count to JavaScript. The
/// Objective-C++ module owns one per JavaScript runtime and calls it on the main queue.
@objc(RNBrudcastInAppBridge)
public final class RNBrudcastInAppBridge: NSObject {
    /// The runtime whose JavaScript set the message handler, so an old runtime cannot answer.
    private static weak var handlerOwner: RNBrudcastInAppBridge?

    /// Messages that crossed to JavaScript, so an inbox message view can draw one by id. Touched
    /// on the main queue.
    static var seen: [String: BrudcastInAppMessage] = [:]

    /// Sends a message request to JavaScript.
    @objc public var emitMessageRequest: ((NSDictionary) -> Void)?

    /// Sends a new unread count to JavaScript.
    @objc public var emitUnreadCount: ((NSNumber) -> Void)?

    private var pending: [String: (BrudcastMessageDecision) -> Void] = [:]
    private var unreadSubscription: AnyCancellable?

    /// Adds the native in-app module to the registry `initialize` reads, when the pod loads.
    @objc public static func registerModule() {
        RNBrudcastModuleRegistry.register(BrudcastInApp.module)
    }

    /// Starts sending the unread count to JavaScript.
    @objc public func moduleCreated() {
        unreadSubscription = Brudcast.inApp.inbox.unreadCountPublisher
            .removeDuplicates()
            .sink { [weak self] count in self?.emitUnreadCount?(NSNumber(value: count)) }
    }

    /// Lets go of this runtime: the message handler is removed, and messages it never answered
    /// show.
    @objc public func invalidate() {
        unreadSubscription = nil
        clearMessageHandler()
        let waiting = pending.values
        pending.removeAll()
        waiting.forEach { $0(.show) }
    }

    @objc public func pauseDisplay() {
        Brudcast.inApp.pauseDisplay()
    }

    @objc public func resumeDisplay() {
        Brudcast.inApp.resumeDisplay()
    }

    @objc public func sync() {
        Brudcast.inApp.sync()
    }

    @objc public func setMessageHandlerEnabled(_ enabled: Bool) {
        guard enabled else { return clearMessageHandler() }
        Self.handlerOwner = self
        Brudcast.inApp.setAsyncMessageHandler { message, decide in
            Self.seen[message.id] = message
            guard let owner = Self.handlerOwner, let emit = owner.emitMessageRequest else { return decide(.show) }
            let requestId = UUID().uuidString
            owner.pending[requestId] = decide
            emit(["requestId": requestId, "message": message.dictionary] as NSDictionary)
        }
    }

    /// Answers a message request with the JavaScript handler's decision.
    ///
    /// - Parameters:
    ///   - requestId: The request's id.
    ///   - decision: `show`, `suppress`, `defer` or `custom`.
    @objc public func resolveMessage(requestId: String, decision: String) {
        guard let decide = pending.removeValue(forKey: requestId) else { return }
        switch decision {
        case "suppress": decide(.suppress)
        case "defer": decide(.defer)
        case "custom": decide(.custom)
        default: decide(.show)
        }
    }

    @objc public func reportImpression(_ messageId: String) {
        Brudcast.inApp.reportImpression(messageId: messageId)
    }

    @objc public func reportClick(_ messageId: String, buttonId: String) {
        Brudcast.inApp.reportClick(messageId: messageId, buttonId: buttonId)
    }

    @objc public func reportDismiss(_ messageId: String) {
        Brudcast.inApp.reportDismiss(messageId: messageId)
    }

    @objc public func presentInbox(title: String) {
        Brudcast.inApp.inbox.present(title: title)
    }

    /// Fetches a page of the inbox.
    ///
    /// - Parameters:
    ///   - beforeMillis: Keeps entries older than this, in epoch milliseconds; nil for the newest.
    ///   - limit: The page size.
    ///   - resolve: Called with the page.
    ///   - reject: Called with an error code and message.
    @objc public func listInbox(
        beforeMillis: NSNumber?,
        limit: Int,
        resolve: @escaping (NSDictionary) -> Void,
        reject: @escaping (String, String) -> Void
    ) {
        let before = beforeMillis.map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        Brudcast.inApp.inbox.list(before: before, limit: limit) { result in
            switch result {
            case .success(let page):
                page.messages.forEach { Self.seen[$0.id] = $0 }
                resolve([
                    "messages": page.messages.map(\.dictionary),
                    "unreadCount": page.unreadCount,
                    "hasMore": page.hasMore,
                ] as NSDictionary)
            case .failure(let error):
                reject(error.code ?? "inbox_failed", error.message)
            }
        }
    }

    @objc public func markRead(_ messageId: String) {
        Brudcast.inApp.inbox.markRead(messageId)
    }

    @objc public func deleteMessage(_ messageId: String) {
        Brudcast.inApp.inbox.delete(messageId)
    }

    @objc public func unreadCount() -> Int {
        Brudcast.inApp.inbox.unreadCount
    }

    private func clearMessageHandler() {
        guard Self.handlerOwner === self else { return }
        Self.handlerOwner = nil
        Brudcast.inApp.setAsyncMessageHandler(nil)
    }
}

/// Draws inbox entries for `BrudcastInboxMessage`.
@objc(RNBrudcastInboxRenderer)
public final class RNBrudcastInboxRenderer: NSObject {
    /// Draws an inbox entry that crossed to JavaScript.
    ///
    /// - Parameters:
    ///   - messageId: The entry's message id.
    ///   - onHeight: Called with the height the design needs, in points, as it changes.
    /// - Returns: The view, or nil when the message is unknown or its design is not supported.
    @objc public static func view(messageId: String, onHeight: @escaping (CGFloat) -> Void) -> UIView? {
        guard let message = RNBrudcastInAppBridge.seen[messageId] else { return nil }
        return Brudcast.inApp.inbox.render(message) { height in onHeight(height) }
    }
}

extension BrudcastInAppMessage {
    /// The message as the spec's `NativeInAppMessage` describes it.
    var dictionary: NSDictionary {
        let format: String
        switch self.format {
        case .modal: format = "modal"
        case .banner: format = "banner"
        case .fullscreen: format = "fullscreen"
        case .inboxOnly: format = "inboxOnly"
        }
        let designJSON = (try? JSONSerialization.data(withJSONObject: design)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var result: [String: Any] = [
            "id": id,
            "format": format,
            "isTest": isTest,
            "title": title,
            "preview": preview,
            "isRead": isRead,
            "createdAtMillis": (createdAt.timeIntervalSince1970 * 1000).rounded(),
            "design": designJSON,
        ]
        if let campaignId = campaignId {
            result["campaignId"] = campaignId
        }
        if let thumbnail = thumbnailURL?.absoluteString {
            result["thumbnailUrl"] = thumbnail
        }
        return result as NSDictionary
    }
}
