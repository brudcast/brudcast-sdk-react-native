import Foundation
import Brudcast

/// What happened in the app that may show a message.
enum InAppOccurrence: Equatable {
    case session
    case event(name: String, properties: BrudcastProperties)
    case screen(name: String, properties: BrudcastProperties)
}

enum TriggerMatcher {
    /// Decides whether an occurrence fires a trigger.
    ///
    /// - Parameters:
    ///   - trigger: The message's trigger.
    ///   - occurrence: What happened.
    /// - Returns: True when the trigger's type and name match and every filter holds.
    static func matches(_ trigger: InAppTrigger, _ occurrence: InAppOccurrence) -> Bool {
        switch (trigger.type, occurrence) {
        case (.onSession, .session):
            return true
        case (.event, .event(let name, let properties)):
            return trigger.eventName == name && filtersHold(trigger.filters, properties)
        case (.screen, .screen(let name, let properties)):
            return trigger.screenName == name && filtersHold(trigger.filters, properties)
        default:
            return false
        }
    }

    static func filtersHold(_ filters: [InAppFilter], _ properties: BrudcastProperties) -> Bool {
        filters.allSatisfy { holds($0, properties[$0.property]) }
    }

    static func holds(_ filter: InAppFilter, _ actual: BrudcastValue?) -> Bool {
        switch filter.op {
        case .exists:
            guard let actual = actual else { return false }
            return actual != .null
        case .eq:
            guard let actual = actual else { return false }
            return equal(actual, filter.value)
        case .neq:
            guard let actual = actual else { return true }
            return !equal(actual, filter.value)
        case .gt:
            guard let lhs = actual?.numberValue, let rhs = filter.value.numberValue else { return false }
            return lhs > rhs
        case .lt:
            guard let lhs = actual?.numberValue, let rhs = filter.value.numberValue else { return false }
            return lhs < rhs
        }
    }

    private static func equal(_ lhs: BrudcastValue, _ rhs: BrudcastValue) -> Bool {
        switch (lhs, rhs) {
        case (.number, _), (_, .number):
            if let left = lhs.numberValue, let right = rhs.numberValue {
                return left == right
            }
            return false
        case (.bool(let left), .string(let right)), (.string(let right), .bool(let left)):
            return String(left) == right.lowercased()
        default:
            return lhs == rhs
        }
    }
}
