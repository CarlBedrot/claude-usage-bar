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

    // Anthropic / Claude palette: clay is the signature accent. Severity
    // escalates within warm tones (clay -> burnt -> brick) — no green.
    static let clay = rgb(217, 119, 87)     // #D97757 — Claude clay (low / primary)
    static let burnt = rgb(190, 74, 31)     // #BE4A1F — mid severity
    static let red = rgb(179, 38, 30)       // #B3261E — high severity
    static let gray = rgb(138, 130, 118)    // #8A8276 — no data
}
