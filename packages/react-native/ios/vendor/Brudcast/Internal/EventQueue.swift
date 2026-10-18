import Foundation

/// The persistent queue of events waiting to be sent.
///
/// The queue does no I/O on the network and owns no thread: the core drives it from its serial
/// queue, asks it for the next batch, and reports how sending went.
final class EventQueue {
    enum Outcome {
        case sent
        case rejected
        case discarded
        case retry
        case unauthorized
    }

    static let maxBatch = 100
    static let flushThreshold = 20
    static let maxStored = 1_000
    static let maxAge: TimeInterval = 7 * 24 * 3_600
    static let baseBackoff: TimeInterval = 2
    static let maxBackoff: TimeInterval = 300

    private static let fileName = "events.json"

    private let storage: BrudcastStorage?
    private let now: () -> Date
    private(set) var pending: [BrudcastEvent]
    private(set) var inFlight: Set<String> = []
    private var failures = 0
    private(set) var retryAfter: Date?
    private(set) var batchLimit = EventQueue.maxBatch
    private var dirty = false

    init(storage: BrudcastStorage?, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.now = now
        let stored = storage?.readJSON(Self.fileName) as? [Any] ?? []
        pending = stored.compactMap(BrudcastEvent.from(stored:))
        dropExpired()
    }

    /// Adds an event. It reaches disk on the next `persistIfNeeded`, so the core decides how often
    /// the file is rewritten.
    ///
    /// - Parameter event: The event.
    /// - Returns: True when enough events are waiting that a flush should start now.
    @discardableResult
    func enqueue(_ event: BrudcastEvent) -> Bool {
        pending.append(event)
        if pending.count > Self.maxStored {
            let overflow = pending.count - Self.maxStored
            BrudcastLogger.shared.warning("Event queue is full, dropping the \(overflow) oldest events")
            pending.removeFirst(overflow)
        }
        dirty = true
        return pending.count - inFlight.count >= Self.flushThreshold
    }

    /// Takes the next batch to send: the oldest waiting events of one channel and one owner, up to
    /// the batch limit.
    ///
    /// - Returns: The batch, or nil when nothing is waiting, a batch is already out, or the queue is
    ///   backing off.
    func nextBatch() -> [BrudcastEvent]? {
        guard inFlight.isEmpty else { return nil }
        if let retryAfter = retryAfter, retryAfter > now() {
            return nil
        }
        dropExpired()
        guard let first = pending.first else { return nil }
        let batch = Array(pending.filter { $0.channel == first.channel && $0.owner == first.owner }.prefix(batchLimit))
        inFlight = Set(batch.map(\.id))
        return batch
    }

    /// Records how sending a batch went.
    ///
    /// - Parameters:
    ///   - batch: The batch `nextBatch` returned.
    ///   - outcome: Sent and discarded batches leave the queue. A rejected batch of several events
    ///     stays and the next batches are halved until the event the service refuses is sent alone
    ///     and dropped. Retried and unauthorized batches stay.
    func complete(_ batch: [BrudcastEvent], outcome: Outcome) {
        let ids = Set(batch.map(\.id))
        inFlight.subtract(ids)
        switch outcome {
        case .sent:
            failures = 0
            retryAfter = nil
            batchLimit = Self.maxBatch
            pending.removeAll { ids.contains($0.id) }
        case .rejected where batch.count > 1:
            failures = 0
            retryAfter = nil
            batchLimit = max(1, batch.count / 2)
        case .rejected, .discarded:
            failures = 0
            retryAfter = nil
            BrudcastLogger.shared.warning("\(batch.count) events could not be sent; they are dropped")
            pending.removeAll { ids.contains($0.id) }
        case .retry:
            failures += 1
            let delay = min(Self.maxBackoff, Self.baseBackoff * pow(2, Double(failures - 1)))
            retryAfter = now().addingTimeInterval(delay)
        case .unauthorized:
            retryAfter = nil
        }
        dirty = true
        persistIfNeeded()
    }

    /// Removes every waiting event.
    func clear() {
        pending.removeAll()
        inFlight.removeAll()
        failures = 0
        retryAfter = nil
        batchLimit = Self.maxBatch
        dirty = true
        persistIfNeeded()
    }

    var waitingCount: Int {
        pending.count
    }

    /// Writes the queue to disk when it changed since the last write.
    func persistIfNeeded() {
        guard dirty else { return }
        dirty = false
        storage?.writeJSON(pending.map(\.storedObject), to: Self.fileName)
    }

    private func dropExpired() {
        let cutoff = now().addingTimeInterval(-Self.maxAge)
        let before = pending.count
        pending.removeAll { $0.occurredAt < cutoff && !inFlight.contains($0.id) }
        if pending.count != before {
            dirty = true
            persistIfNeeded()
        }
    }
}
