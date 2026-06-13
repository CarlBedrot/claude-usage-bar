import AppKit
import SwiftUI
import UsageCore

/// Debug helper: render the popover with representative sample data to a PNG and
/// exit. Invoked via `ClaudeUsageBar --render-png <path>`. Never touches the
/// network, Keychain, or status bar — purely for visual verification.
@MainActor
func renderSamplePNG(to path: String) {
    let now = Date()
    let limits = Limits(
        fiveHour: Limit(utilization: 63, resetsAt: now.addingTimeInterval(2 * 3600)),
        sevenDay: Limit(utilization: 91, resetsAt: now.addingTimeInterval(2 * 86400)),
        sevenDaySonnet: nil)
    let today: PerModelCounts = [
        "claude-opus-4-8": Counts(input: 70_000, output: 220_000,
                                  cacheRead: 48_000_000, cacheWrite: 2_500_000),
    ]
    let session = Counts(input: 51_000, output: 85_000,
                         cacheRead: 19_000_000, cacheWrite: 1_400_000)
    let snapshot = UsageSnapshot(
        state: .ok(limits), cache: .missing,
        todayByModel: today, sessionTotals: session)

    let model = UsageModel(seed: snapshot)
    let content = UsageView(model: model, onQuit: {})
        .background(Color(nsColor: .windowBackgroundColor))

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2.0

    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
}
