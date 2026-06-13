import SwiftUI

/// Fixed warm "cream + ink" palette. Deliberately not appearance-adaptive: the
/// popover always renders cream with dark text in both light and dark mode, with
/// high-contrast severity colors that read clearly on cream.
enum Palette {
    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    static let cream = rgb(244, 241, 234)   // #F4F1EA — popover background
    static let panel = rgb(233, 227, 214)   // #E9E3D6 — neutral token card
    static let ink = rgb(31, 27, 22)        // #1F1B16 — primary text (warm black)
    static let inkDim = rgb(122, 112, 96)   // #7A7060 — secondary text

    static let green = rgb(22, 130, 54)     // #168236
    static let amber = rgb(193, 112, 0)     // #C17000
    static let red = rgb(197, 34, 31)       // #C5221F
    static let gray = rgb(138, 130, 118)    // #8A8276
}
