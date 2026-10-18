import Foundation
import Combine
import Brudcast
#if canImport(UIKit)
import UIKit
#endif

/// One page of the inbox, newest first.
public struct BrudcastInboxPage {
    public let messages: [BrudcastInAppMessage]
    public let unreadCount: Int
    public let hasMore: Bool
}

/// The in-app inbox: messages to read later, kept by the service across devices.
public final class BrudcastInbox {
    private weak var module: BrudcastInApp?
    private var context: BrudcastContext?
    private let unread = CurrentValueSubject<Int, Never>(0)
    private var entries: [String: InAppMessage] = [:]
    private let lock = NSLock()

    init() {}

    func attach(module: BrudcastInApp, context: BrudcastContext) {
        self.module = module
        self.context = context
    }

    /// The number of unread entries, as last reported by the service. Read it on the main queue.
    public var unreadCount: Int {
        unread.value
    }

    /// Publishes the unread count on the main queue whenever it changes.
    public var unreadCountPublisher: AnyPublisher<Int, Never> {
        unread.removeDuplicates().receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    /// Fetches a page of the inbox.
    ///
    /// - Parameters:
    ///   - before: Return entries older than this, for the next page. Nil for the newest.
    ///   - limit: At most this many entries, up to 100.
    ///   - completion: Called on the main queue with the page or the error.
    public func list(before: Date? = nil, limit: Int = 20, completion: @escaping (Result<BrudcastInboxPage, BrudcastApiError>) -> Void) {
        guard let context = context else {
            DispatchQueue.main.async {
                completion(.failure(BrudcastApiError(statusCode: nil, code: "not_initialized", message: "BrudcastInApp.module is not installed")))
            }
            return
        }
        var query = ["limit": String(min(max(limit, 1), 100))]
        if let before = before {
            query["before"] = BrudcastDates.format(before)
        }
        context.queue.async {
            context.request(.get, "/inbox", query: query) { result in
                let mapped = result.map { payload -> BrudcastInboxPage in
                    let parsed = (payload["messages"] as? [Any] ?? []).compactMap(InAppMessage.parse)
                    self.remember(parsed)
                    let count = (payload["unreadCount"] as? NSNumber)?.intValue ?? 0
                    self.publish(count)
                    return BrudcastInboxPage(messages: parsed.map(\.publicMessage), unreadCount: count, hasMore: payload["hasMore"] as? Bool ?? false)
                }
                DispatchQueue.main.async { completion(mapped) }
            }
        }
    }

    /// Marks an entry read.
    ///
    /// - Parameter messageId: The entry's message id.
    public func markRead(_ messageId: String) {
        guard let context = context else { return }
        context.queue.async {
            guard let entry = self.entry(messageId), !entry.read else { return }
            self.update(messageId) { $0.read = true }
            self.publish(max(0, self.unread.value - 1))
            self.module?.inboxMessageOpened(entry)
            context.enqueue(BrudcastEvent(type: "inbox_read", messageId: messageId, channel: BrudcastInApp.eventChannel))
            context.flush()
        }
    }

    /// Deletes an entry from the inbox on every device.
    ///
    /// - Parameter messageId: The entry's message id.
    public func delete(_ messageId: String) {
        guard let context = context else { return }
        context.queue.async {
            let entry = self.entry(messageId)
            self.lock.lock()
            self.entries[messageId] = nil
            self.lock.unlock()
            if entry?.read == false {
                self.publish(max(0, self.unread.value - 1))
            }
            context.enqueue(BrudcastEvent(type: "inbox_delete", messageId: messageId, channel: BrudcastInApp.eventChannel))
            context.flush()
        }
    }

    func refreshUnreadCount() {
        guard let context = context else { return }
        context.request(.get, "/inbox", query: ["limit": "1"]) { result in
            if case .success(let payload) = result, let count = (payload["unreadCount"] as? NSNumber)?.intValue {
                self.publish(count)
            }
        }
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        publish(0)
    }

    func entry(_ id: String) -> InAppMessage? {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]
    }

    private func remember(_ messages: [InAppMessage]) {
        lock.lock()
        for message in messages {
            entries[message.id] = message
        }
        lock.unlock()
    }

    private func update(_ id: String, _ change: (inout InAppMessage) -> Void) {
        lock.lock()
        if var entry = entries[id] {
            change(&entry)
            entries[id] = entry
        }
        lock.unlock()
    }

    private func publish(_ count: Int) {
        unread.send(count)
    }

    #if canImport(UIKit)
    /// Presents the default inbox screen as a sheet.
    ///
    /// - Parameters:
    ///   - presenter: The view controller to present from. The topmost one is used when nil.
    ///   - title: The screen title.
    public func present(from presenter: UIViewController? = nil, title: String = "Inbox") {
        DispatchQueue.main.async {
            guard let host = presenter ?? BrudcastPresentation.topViewController() else {
                BrudcastLogger.shared.warning("There is no view controller to present the inbox from")
                return
            }
            host.present(InboxScreen.make(inbox: self, title: title), animated: true)
        }
    }

    /// Draws an inbox entry's design with the standard renderer, for a custom inbox.
    ///
    /// - Parameter message: An entry from `list`.
    /// - Returns: The view, which keeps its renderer alive for as long as it lives, or nil when the
    ///   design cannot be drawn.
    public func render(_ message: BrudcastInAppMessage) -> UIView? {
        guard let stored = entry(message.id), let design = stored.design else { return nil }
        return InboxDetailContainerView(controller: InboxScreen.detail(design: design, messageId: stored.id, inbox: self))
    }

    /// Draws an inbox entry's design with the standard renderer and reports the height it needs, so
    /// a custom inbox can size the view to fit. The view scrolls when it is given less.
    ///
    /// - Parameters:
    ///   - message: An entry from `list`.
    ///   - onContentHeightChange: Called on the main queue with the height in points the design
    ///     needs at the view's width, whenever it changes.
    /// - Returns: The view, which keeps its renderer alive for as long as it lives, or nil when the
    ///   design cannot be drawn.
    public func render(_ message: BrudcastInAppMessage, onContentHeightChange: @escaping (CGFloat) -> Void) -> UIView? {
        guard let stored = entry(message.id), let design = stored.design else { return nil }
        let controller = InboxScreen.detail(design: design, messageId: stored.id, inbox: self, onContentHeightChange: onContentHeightChange)
        return InboxDetailContainerView(controller: controller)
    }

    func open(_ message: BrudcastInAppMessage, from navigation: UINavigationController?) {
        guard let stored = entry(message.id), let design = stored.design else { return }
        markRead(message.id)
        navigation?.pushViewController(InboxScreen.detail(design: design, messageId: stored.id, inbox: self), animated: true)
    }

    func buttonTapped(messageId: String, buttonId: String?, action: InAppAction) {
        context?.queue.async {
            self.module?.handleButton(messageId: messageId, buttonId: buttonId, action: action)
        }
    }
    #endif
}
