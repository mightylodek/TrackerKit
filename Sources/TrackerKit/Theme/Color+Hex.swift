import SwiftUI
import UIKit

public extension Color {

    /// Builds a color from `#RRGGBB`, `#RRGGBBAA`, or the same without the hash.
    /// Malformed input falls back to gray rather than trapping — a bad hex in
    /// stored data should never crash a chart.
    init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard let value = UInt64(cleaned, radix: 16), cleaned.count == 6 || cleaned.count == 8 else {
            self = .gray
            return
        }

        let red, green, blue, alpha: Double
        if cleaned.count == 6 {
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
            alpha = 1
        } else {
            red = Double((value & 0xFF00_0000) >> 24) / 255
            green = Double((value & 0x00FF_0000) >> 16) / 255
            blue = Double((value & 0x0000_FF00) >> 8) / 255
            alpha = Double(value & 0x0000_00FF) / 255
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// A color that resolves differently in light and dark mode.
    ///
    /// The palette ships *selected* dark steps rather than algorithmically
    /// lightening the light ones — dark mode is designed, not flipped.
    init(light: String, dark: String) {
        #if os(watchOS)
        // watchOS has no light appearance — the system is always dark, and there
        // is no trait-based dynamic provider to resolve against. Taking the dark
        // step is the right answer on that platform, not a degraded fallback.
        self.init(hex: dark)
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
        #endif
    }

    /// `#RRGGBB` round-trip, used when persisting a picked color.
    var hexString: String {
        let components = UIColor(self).cgColor.components ?? [0, 0, 0, 1]
        let red = Float(components.count > 2 ? components[0] : 0)
        let green = Float(components.count > 2 ? components[1] : 0)
        let blue = Float(components.count > 2 ? components[2] : 0)
        return String(format: "#%02lX%02lX%02lX",
                      lroundf(red * 255), lroundf(green * 255), lroundf(blue * 255))
    }
}
