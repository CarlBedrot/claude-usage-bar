import AppKit
import SwiftUI
import UsageCore

// Limits cover 5h / 7d windows and move slowly, so poll gently — frequent
// polling trips the usage endpoint's rate limit (HTTP 429). The popover also
// refreshes when opened, so you get fresh numbers exactly when you look.
let refreshIntervalSeconds: TimeInterval = 300

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
        popover.appearance = NSAppearance(named: .aqua)  // keep the cream UI light in dark mode too
        let hosting = NSHostingController(
            rootView: UsageView(model: model, onQuit: { NSApp.terminate(nil) }))
        hosting.sizingOptions = [.preferredContentSize]  // popover auto-fits the content height
        popover.contentViewController = hosting

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
            severity = .high
        case .fetchError:
            severity = .unknown
        }
        let attributed = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: Palette.nsColor(for: severity)])
        button.attributedTitle = attributed
    }
}

// The app entry point. NSApplication runs on the main thread; assume main-actor
// isolation so we can construct the main-actor-isolated AppDelegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    // Keep the delegate alive for the lifetime of the app.
    app.delegate = delegate
    objc_setAssociatedObject(app, "delegate-strong", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
