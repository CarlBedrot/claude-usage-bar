import SwiftUI
import AppKit
import UsageCore

/// Fixed warm "cream + ink" palette, the single source of truth for colors.
/// Deliberately not appearance-adaptive: the popover renders cream with dark
/// text in both light and dark mode, with high-contrast severity colors.
enum Palette {
    // sRGB component triples — defined once, used for both SwiftUI and AppKit.
    private static let creamRGB  = (244.0, 241.0, 234.0)   // #F4F1EA — background
    private static let panelRGB  = (233.0, 227.0, 214.0)   // #E9E3D6 — token card
    private static let inkRGB    = (31.0, 27.0, 22.0)      // #1F1B16 — primary text
    private static let inkDimRGB = (122.0, 112.0, 96.0)    // #7A7060 — secondary text
    private static let clayRGB   = (217.0, 119.0, 87.0)    // #D97757 — low / Claude clay
    private static let burntRGB  = (190.0, 74.0, 31.0)     // #BE4A1F — mid
    private static let brickRGB  = (179.0, 38.0, 30.0)     // #B3261E — high
    private static let grayRGB   = (138.0, 130.0, 118.0)   // #8A8276 — no data

    static let cream  = color(creamRGB)
    static let panel  = color(panelRGB)
    static let ink    = color(inkRGB)
    static let inkDim = color(inkDimRGB)
    static let clay   = color(clayRGB)

    /// SwiftUI color for a severity — used in the popover cards.
    static func color(for severity: Severity) -> Color {
        color(rgb(for: severity))
    }

    /// AppKit color for a severity — used for the menu bar title.
    static func nsColor(for severity: Severity) -> NSColor {
        guard severity != .unknown else {
            return .secondaryLabelColor
        }
        let c = rgb(for: severity)
        return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
    }

    private static func rgb(for severity: Severity) -> (Double, Double, Double) {
        switch severity {
        case .low: return clayRGB
        case .mid: return burntRGB
        case .high: return brickRGB
        case .unknown: return grayRGB
        }
    }

    private static func color(_ c: (Double, Double, Double)) -> Color {
        Color(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255)
    }
}
