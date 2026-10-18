import Foundation

/// One event bound for `POST /sdk/v1/events`.
public struct BrudcastEvent: Equatable {
    public let id: String
    public let type: String
    public let messageId: String?
    public let buttonId: String?
    public let name: String?
    public let properties: BrudcastProperties
    public let occurredAt: Date
    public let channel: String

    /// The external id of the user signed in when the event was queued, or nil for an anonymous
    /// user. The core sets it, so a batch is only ever sent with that user's session.
    var owner: String?

    /// - Parameters:
    ///   - type: The event type, such as `impression`.
    ///   - messageId: The message the event is about, when it is about one.
    ///   - buttonId: The tapped button, for clicks.
    ///   - name: The event or screen name, for `custom` and `screen` events.
    ///   - properties: Event properties.
    ///   - occurredAt: When it happened.
    ///   - channel: Which batch the event travels in. Events of different channels never share a
    ///     batch, so a type one deployment of the service does not accept cannot fail the others.
    ///   - id: The client id the service deduplicates on.
    public init(
        type: String,
        messageId: String? = nil,
        buttonId: String? = nil,
        name: String? = nil,
        properties: BrudcastProperties = [:],
        occurredAt: Date = Date(),
        channel: String = BrudcastEvent.coreChannel,
        id: String = UUID().uuidString.lowercased()
    ) {
        self.id = id
        self.type = type
        self.messageId = messageId
        self.buttonId = buttonId
        self.name = name
        self.properties = properties
        self.occurredAt = occurredAt
        self.channel = channel
    }

    public static let coreChannel = "core"

    var apiObject: [String: Any] {
        var object: [String: Any] = [
            "id": id,
            "type": type,
            "occurredAt": BrudcastDates.format(occurredAt),
        ]
        object["messageId"] = messageId
        object["buttonId"] = buttonId
        object["name"] = name
        if !properties.isEmpty {
            object["properties"] = properties.jsonObject
        }
        return object
    }

    var storedObject: [String: Any] {
        var object = apiObject
        object["channel"] = channel
        object["owner"] = owner
        return object
    }

    static func from(stored: Any) -> BrudcastEvent? {
        guard let object = stored as? [String: Any],
              let id = object["id"] as? String,
              let type = object["type"] as? String,
              let occurredAtRaw = object["occurredAt"] as? String,
              let occurredAt = BrudcastDates.parse(occurredAtRaw) else {
            return nil
        }
        var event = BrudcastEvent(
            type: type,
            messageId: object["messageId"] as? String,
            buttonId: object["buttonId"] as? String,
            name: object["name"] as? String,
            properties: .from(json: object["properties"]),
            occurredAt: occurredAt,
            channel: object["channel"] as? String ?? coreChannel,
            id: id
        )
        event.owner = object["owner"] as? String
        return event
    }
}

/// ISO 8601 dates with milliseconds, as the service writes and reads them.
public enum BrudcastDates {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let lock = NSLock()

    /// Formats a date as ISO 8601 with milliseconds in UTC.
    ///
    /// - Parameter date: The date.
    /// - Returns: The formatted string.
    public static func format(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return withFraction.string(from: date)
    }

    /// Parses an ISO 8601 date with or without fractional seconds.
    ///
    /// - Parameter string: The string.
    /// - Returns: The date, or nil when the string is not a date.
    public static func parse(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return withFraction.date(from: string) ?? withoutFraction.date(from: string)
    }
}
