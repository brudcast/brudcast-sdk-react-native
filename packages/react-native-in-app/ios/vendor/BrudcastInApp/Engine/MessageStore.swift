import Foundation
import Brudcast

struct FrequencyCap: Equatable {
    var count: Int
    var hours: Double
    var impressionsInWindow: Int

    static func parse(_ raw: Any?) -> FrequencyCap? {
        guard let object = raw as? [String: Any],
              let count = (object["count"] as? NSNumber)?.intValue,
              let hours = (object["hours"] as? NSNumber)?.doubleValue,
              count > 0, hours > 0 else {
            return nil
        }
        return FrequencyCap(count: count, hours: hours, impressionsInWindow: (object["impressionsInWindow"] as? NSNumber)?.intValue ?? 0)
    }

    var jsonObject: [String: Any] {
        ["count": count, "hours": hours, "impressionsInWindow": impressionsInWindow]
    }
}

/// The messages this device holds, and the local record of what it has shown.
///
/// The service's counts are authoritative but lag behind events still waiting in the queue, so
/// every limit takes the larger of the service's figure and the local one.
final class MessageStore {
    private static let feedFile = "in_app_feed.json"
    private static let stateFile = "in_app_state.json"
    private static let ledgerWindow: TimeInterval = 168 * 3_600

    private let storage: BrudcastStorage?
    private let now: () -> Date

    private(set) var messages: [InAppMessage] = []
    private(set) var frequencyCap: FrequencyCap?
    private(set) var userId: String?
    private var rawMessages: [Any] = []
    private var localImpressions: [String: Int] = [:]
    private var ledger: [Date] = []
    private var impressionsSinceSync = 0
    private var delivered: Set<String> = []
    private var reportedUnsupported: Set<String> = []

    init(storage: BrudcastStorage?, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.now = now
        load()
    }

    struct Change {
        var added: [InAppMessage]
        var removed: [String]
    }

    /// Replaces the held messages with a feed from the service. Anything absent was withdrawn.
    ///
    /// - Parameters:
    ///   - raw: The feed's `messages` array.
    ///   - frequencyCap: The feed's `frequencyCap`.
    ///   - userId: The session's user, so a different user's messages are never kept.
    /// - Returns: Which messages are new to this device, and which ids went away.
    @discardableResult
    func replace(raw: [Any], frequencyCap: Any?, userId: String) -> Change {
        if self.userId != userId {
            clearUserState()
            self.userId = userId
        }
        let parsed = raw.compactMap(InAppMessage.parse)
        let oldIds = Set(messages.map(\.id))
        let newIds = Set(parsed.map(\.id))
        let added = parsed.filter { !oldIds.contains($0.id) }
        let removed = messages.map(\.id).filter { !newIds.contains($0) }
        messages = parsed
        rawMessages = raw
        self.frequencyCap = FrequencyCap.parse(frequencyCap)
        impressionsSinceSync = 0
        localImpressions = localImpressions.filter { newIds.contains($0.key) }
        persist()
        return Change(added: added, removed: removed)
    }

    func message(_ id: String) -> InAppMessage? {
        messages.first { $0.id == id }
    }

    /// Marks messages as delivered.
    ///
    /// - Parameter ids: Message ids just stored.
    /// - Returns: The ids not delivered before, which need a `delivered` event.
    func markDelivered(_ ids: [String]) -> [String] {
        let fresh = ids.filter { !delivered.contains($0) }
        guard !fresh.isEmpty else { return [] }
        delivered.formUnion(fresh)
        let held = Set(messages.map(\.id))
        if delivered.count > 2_000 {
            delivered = delivered.filter { held.contains($0) }
        }
        persist()
        return fresh
    }

    /// Marks an unsupported design as reported.
    ///
    /// - Parameter id: The message id.
    /// - Returns: True the first time, when the `render_unsupported` event should be sent.
    func markUnsupportedReported(_ id: String) -> Bool {
        guard reportedUnsupported.insert(id).inserted else { return false }
        persist()
        return true
    }

    func recordImpression(_ id: String) {
        let current = now()
        let count = impressionCount(id) + 1
        localImpressions[id] = count
        ledger.append(current)
        impressionsSinceSync += 1
        ledger.removeAll { current.timeIntervalSince($0) > Self.ledgerWindow }
        persist()
    }

    func markRead(_ id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].read = true
    }

    func impressionCount(_ id: String) -> Int {
        max(message(id)?.impressionCount ?? 0, localImpressions[id] ?? 0)
    }

    /// Decides whether a message may be shown now.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - serverNow: The current time on the service's clock.
    /// - Returns: True when it is a displayable design inside its window and under every limit.
    func isEligible(_ message: InAppMessage, serverNow: Date) -> Bool {
        guard message.display, message.format != .inboxOnly, message.design != nil else { return false }
        if let startsAt = message.startsAt, startsAt > serverNow { return false }
        if let endsAt = message.endsAt, endsAt < serverNow { return false }
        if message.test { return true }
        guard impressionCount(message.id) < message.displayRules.maxImpressions else { return false }
        if let cap = frequencyCap {
            let windowStart = now().addingTimeInterval(-cap.hours * 3_600)
            let local = ledger.filter { $0 >= windowStart }.count
            let inWindow = max(cap.impressionsInWindow + impressionsSinceSync, local)
            guard inWindow < cap.count else { return false }
        }
        return true
    }

    func clearUserState() {
        messages = []
        rawMessages = []
        frequencyCap = nil
        localImpressions = [:]
        impressionsSinceSync = 0
        delivered = []
        reportedUnsupported = []
        persist()
    }

    private func load() {
        if let feed = storage?.readJSON(Self.feedFile) as? [String: Any] {
            userId = feed["userId"] as? String
            rawMessages = feed["messages"] as? [Any] ?? []
            messages = rawMessages.compactMap(InAppMessage.parse)
            frequencyCap = FrequencyCap.parse(feed["frequencyCap"])
        }
        if let state = storage?.readJSON(Self.stateFile) as? [String: Any] {
            localImpressions = (state["impressions"] as? [String: NSNumber] ?? [:]).mapValues(\.intValue)
            ledger = (state["ledger"] as? [String] ?? []).compactMap(BrudcastDates.parse)
            impressionsSinceSync = (state["sinceSync"] as? NSNumber)?.intValue ?? 0
            delivered = Set(state["delivered"] as? [String] ?? [])
            reportedUnsupported = Set(state["unsupported"] as? [String] ?? [])
        }
    }

    private func persist() {
        guard let storage = storage else { return }
        var feed: [String: Any] = ["messages": rawMessages]
        feed["userId"] = userId
        feed["frequencyCap"] = frequencyCap?.jsonObject
        storage.writeJSON(feed, to: Self.feedFile)
        storage.writeJSON([
            "impressions": localImpressions,
            "ledger": ledger.map(BrudcastDates.format),
            "sinceSync": impressionsSinceSync,
            "delivered": Array(delivered),
            "unsupported": Array(reportedUnsupported),
        ] as [String: Any], to: Self.stateFile)
    }
}
