import Foundation
import Brudcast

enum InAppTriggerType: String {
    case onSession = "on_session"
    case event
    case screen
}

enum InAppFilterOperator: String {
    case eq
    case neq
    case gt
    case lt
    case exists
}

struct InAppFilter: Equatable {
    var property: String
    var op: InAppFilterOperator
    var value: BrudcastValue
}

struct InAppTrigger: Equatable {
    var type: InAppTriggerType
    var eventName: String?
    var screenName: String?
    var filters: [InAppFilter]

    static let onSession = InAppTrigger(type: .onSession, eventName: nil, screenName: nil, filters: [])

    /// Stands in for a trigger this SDK cannot read; no occurrence ever matches it.
    static let unreadable = InAppTrigger(type: .event, eventName: nil, screenName: nil, filters: [])

    static func parse(_ raw: Any?) -> InAppTrigger? {
        guard let object = raw as? [String: Any] else { return .onSession }
        guard let type = InAppTriggerType(rawValue: object["type"] as? String ?? "on_session") else { return nil }
        var filters: [InAppFilter] = []
        for rawFilter in object["filters"] as? [Any] ?? [] {
            guard let filter = rawFilter as? [String: Any],
                  let property = filter["property"] as? String,
                  let op = (filter["operator"] as? String).flatMap(InAppFilterOperator.init(rawValue:)) else {
                return nil
            }
            filters.append(InAppFilter(property: property, op: op, value: BrudcastValue.from(filter["value"]) ?? .null))
        }
        return InAppTrigger(
            type: type,
            eventName: object["eventName"] as? String,
            screenName: object["screenName"] as? String,
            filters: filters
        )
    }
}

enum InAppPriority: String {
    case low
    case normal
    case high

    var rank: Int {
        switch self {
        case .low: return 0
        case .normal: return 1
        case .high: return 2
        }
    }
}

struct InAppDisplayRules: Equatable {
    var maxImpressions: Int
    var delaySeconds: Double
    var priority: InAppPriority

    static func parse(_ raw: Any?) -> InAppDisplayRules {
        let object = raw as? [String: Any] ?? [:]
        return InAppDisplayRules(
            maxImpressions: max(1, (object["maxImpressions"] as? NSNumber)?.intValue ?? 1),
            delaySeconds: max(0, (object["delaySeconds"] as? NSNumber)?.doubleValue ?? 0),
            priority: (object["priority"] as? String).flatMap(InAppPriority.init(rawValue:)) ?? .normal
        )
    }
}

/// How the design of a stored message turned out.
enum InAppDesignState: Equatable {
    case ready(InAppDesign)
    case unsupported(InAppDesignError)
}

/// One message the service told this device to hold.
struct InAppMessage: Equatable {
    var id: String
    var kind: String
    var campaignId: String?
    var test: Bool
    var format: InAppFormat
    var designState: InAppDesignState
    var rawDesign: [String: Any]
    var trigger: InAppTrigger
    var displayRules: InAppDisplayRules
    var inboxTitle: String
    var inboxPreview: String
    var inboxThumbnailURL: URL?
    var display: Bool
    var inboxEntry: Bool
    var read: Bool
    var impressionCount: Int
    var startsAt: Date?
    var endsAt: Date?
    var createdAt: Date
    var triggerUnreadable = false

    var design: InAppDesign? {
        if case .ready(let design) = designState {
            return design
        }
        return nil
    }

    static func == (lhs: InAppMessage, rhs: InAppMessage) -> Bool {
        lhs.id == rhs.id && lhs.designState == rhs.designState && lhs.trigger == rhs.trigger
            && lhs.displayRules == rhs.displayRules && lhs.display == rhs.display && lhs.read == rhs.read
            && lhs.impressionCount == rhs.impressionCount && lhs.startsAt == rhs.startsAt && lhs.endsAt == rhs.endsAt
    }

    /// Reads one entry of a feed or inbox page.
    ///
    /// - Parameter raw: The decoded message view.
    /// - Returns: The message, or nil when it lacks an id or a format. A design this SDK cannot draw,
    ///   or a trigger it cannot read, still yields a message that never shows on its own, so it can
    ///   be reported.
    static func parse(_ raw: Any) -> InAppMessage? {
        guard let object = raw as? [String: Any],
              let id = object["id"] as? String,
              let format = (object["format"] as? String).flatMap(InAppFormat.init(rawValue:)) else {
            return nil
        }
        let parsedTrigger = InAppTrigger.parse(object["trigger"])
        let rawDesign = object["design"] as? [String: Any] ?? [:]
        let designState: InAppDesignState
        do {
            designState = .ready(try InAppDesign.parse(rawDesign))
        } catch let error as InAppDesignError {
            designState = .unsupported(error)
        } catch {
            designState = .unsupported(.empty)
        }
        let inbox = object["inbox"] as? [String: Any] ?? [:]
        return InAppMessage(
            id: id,
            kind: object["kind"] as? String ?? "campaign",
            campaignId: object["campaignId"] as? String,
            test: object["test"] as? Bool ?? false,
            format: format,
            designState: designState,
            rawDesign: rawDesign,
            trigger: parsedTrigger ?? .unreadable,
            displayRules: InAppDisplayRules.parse(object["displayRules"]),
            inboxTitle: inbox["title"] as? String ?? "",
            inboxPreview: inbox["preview"] as? String ?? "",
            inboxThumbnailURL: (inbox["thumbnailUrl"] as? String).flatMap(URL.init(string:)),
            display: object["display"] as? Bool ?? (format != .inboxOnly),
            inboxEntry: object["inboxEntry"] as? Bool ?? false,
            read: object["read"] as? Bool ?? false,
            impressionCount: (object["impressionCount"] as? NSNumber)?.intValue ?? 0,
            startsAt: BrudcastDates.parse(object["startsAt"] as? String),
            endsAt: BrudcastDates.parse(object["endsAt"] as? String),
            createdAt: BrudcastDates.parse(object["createdAt"] as? String) ?? Date(),
            triggerUnreadable: parsedTrigger == nil
        )
    }

    var publicMessage: BrudcastInAppMessage {
        BrudcastInAppMessage(
            id: id,
            campaignId: campaignId,
            format: format,
            isTest: test,
            title: inboxTitle.isEmpty ? (design?.title ?? "") : inboxTitle,
            preview: inboxPreview.isEmpty ? (design?.bodyText ?? "") : inboxPreview,
            thumbnailURL: inboxThumbnailURL ?? design?.firstImageURL,
            isRead: read,
            createdAt: createdAt,
            design: rawDesign
        )
    }
}

/// A message as the host app sees it, in the message handler and the inbox.
public struct BrudcastInAppMessage {
    public let id: String
    public let campaignId: String?
    public let format: InAppFormat
    public let isTest: Bool
    public let title: String
    public let preview: String
    public let thumbnailURL: URL?
    public let isRead: Bool
    public let createdAt: Date
    /// The design document, for apps that draw messages themselves.
    public let design: [String: Any]
}
