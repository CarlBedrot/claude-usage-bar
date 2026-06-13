import AppKit
import SwiftUI
import UsageCore

let refreshIntervalSeconds: TimeInterval = 60

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timer: Timer?
    private let model = UsageModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "⚡ …"
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: UsageView(model: model, onQuit: { NSApp.terminate(nil) }))

        // Re-render the status item title whenever the model publishes.
        model.onUpdate = { [weak self] snapshot in
            self?.updateTitle(snapshot)
        }

        model.refresh()
        startTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self = self else {
                return
            }
            Task { @MainActor in
                self.model.refresh()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        model.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Color the menu bar title by worst severity via an attributed string.
    private func updateTitle(_ snapshot: UsageSnapshot) {
        guard let button = statusItem.button else {
            return
        }
        let text = menuLine(state: snapshot.state)
        let severity: Severity
        switch snapshot.state {
        case .ok(let limits):
            severity = menuSeverity(limits)
        case .authError:
            severity = .red
        case .fetchError:
            severity = .gray
        }
        let attributed = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: nsColor(for: severity)])
        button.attributedTitle = attributed
    }

    private func nsColor(for severity: Severity) -> NSColor {
        switch severity {
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .red:
            return .systemRed
        case .gray:
            return .secondaryLabelColor
        }
    }
}

// The app entry point. NSApplication runs on the main thread; assume main-actor
// isolation so we can construct the main-actor-isolated AppDelegate.
MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--render-png"), i + 1 < args.count {
        renderSamplePNG(to: args[i + 1])
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    // Keep the delegate alive for the lifetime of the app.
    app.delegate = delegate
    objc_setAssociatedObject(app, "delegate-strong", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
