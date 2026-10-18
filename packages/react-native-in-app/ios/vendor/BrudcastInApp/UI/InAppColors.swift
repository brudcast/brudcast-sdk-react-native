import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Parses `#RRGGBB` and `#RRGGBBAA` colours.
enum InAppHexColor {
    /// - Parameter hex: The colour string.
    /// - Returns: Red, green, blue and alpha from 0 to 1, or nil when the string is not a colour.
    static func components(_ hex: String?) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard var value = hex?.trimmingCharacters(in: .whitespaces), value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        if value.count == 6 {
            return (Double((number >> 16) & 0xFF) / 255, Double((number >> 8) & 0xFF) / 255, Double(number & 0xFF) / 255, 1)
        }
        return (Double((number >> 24) & 0xFF) / 255, Double((number >> 16) & 0xFF) / 255, Double((number >> 8) & 0xFF) / 255, Double(number & 0xFF) / 255)
    }

    /// The relative luminance of a colour, from 0 for black to 1 for white.
    ///
    /// - Parameter components: The colour.
    /// - Returns: The WCAG relative luminance.
    static func luminance(_ components: (red: Double, green: Double, blue: Double, alpha: Double)) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(components.red) + 0.7152 * channel(components.green) + 0.0722 * channel(components.blue)
    }
}

#if canImport(UIKit)
extension UIColor {
    /// A colour from a design, adapting to dark mode when a dark variant is given.
    ///
    /// - Parameters:
    ///   - hex: The light colour.
    ///   - darkHex: The dark colour, or nil to use the light one in both.
    /// - Returns: The colour, or nil when the light colour does not parse.
    static func brudcast(_ hex: String?, dark darkHex: String? = nil) -> UIColor? {
        guard let light = InAppHexColor.components(hex).map(UIColor.init(components:)) else { return nil }
        guard let dark = InAppHexColor.components(darkHex).map(UIColor.init(components:)) else { return light }
        return UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }

    convenience init(components: (red: Double, green: Double, blue: Double, alpha: Double)) {
        self.init(red: components.red, green: components.green, blue: components.blue, alpha: components.alpha)
    }

    /// Black or white, whichever reads better on this colour.
    var contrastingLabel: UIColor {
        UIColor { traits in
            let resolved = self.resolvedColor(with: traits)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let luminance = InAppHexColor.luminance((Double(red), Double(green), Double(blue), Double(alpha)))
            return luminance > 0.45 ? .black : .white
        }
    }
}
#endif
