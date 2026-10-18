import Foundation

/// A property value the Brudcast API accepts: a string, a number, a boolean or null.
public enum BrudcastValue: Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// Converts a JSON value decoded by `JSONSerialization` into a property value.
    ///
    /// - Parameter any: The decoded value.
    /// - Returns: The matching value, or `nil` when the value is an array, an object or another type.
    public static func from(_ any: Any?) -> BrudcastValue? {
        switch any {
        case nil, is NSNull:
            return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .number(Double(int))
        case let double as Double:
            return .number(double)
        default:
            return nil
        }
    }

    /// Returns the value in the form `JSONSerialization` writes.
    ///
    /// - Returns: A `String`, an `NSNumber` or `NSNull`. A NaN or infinite number becomes `NSNull`,
    ///   because JSON cannot carry it and `JSONSerialization` raises an exception on it.
    public var jsonObject: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            guard value.isFinite else {
                return NSNull()
            }
            if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
                return NSNumber(value: Int64(value))
            }
            return NSNumber(value: value)
        case .bool(let value):
            return NSNumber(value: value)
        case .null:
            return NSNull()
        }
    }

    /// The value as a number, when it is a number or a string that parses as one.
    public var numberValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value)
        default:
            return nil
        }
    }
}

extension BrudcastValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension BrudcastValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension BrudcastValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension BrudcastValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension BrudcastValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

public typealias BrudcastProperties = [String: BrudcastValue]

extension Dictionary where Key == String, Value == BrudcastValue {
    var jsonObject: [String: Any] {
        mapValues { $0.jsonObject }
    }

    /// Drops NaN and infinite numbers, which JSON cannot carry, and logs each one dropped.
    ///
    /// - Returns: The properties without them.
    func droppingNonFiniteNumbers() -> BrudcastProperties {
        filter { key, value in
            guard case .number(let number) = value, !number.isFinite else { return true }
            BrudcastLogger.shared.warning("Property \"\(key)\" is \(number), which JSON cannot carry; it is dropped")
            return false
        }
    }

    static func from(json: Any?) -> BrudcastProperties {
        guard let object = json as? [String: Any] else { return [:] }
        var properties: BrudcastProperties = [:]
        for (key, raw) in object {
            if let value = BrudcastValue.from(raw) {
                properties[key] = value
            }
        }
        return properties
    }
}
