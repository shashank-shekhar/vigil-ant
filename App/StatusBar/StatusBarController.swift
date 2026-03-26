internal import AppKit
import SwiftUI
import CIStatusKit

/// Manages the NSStatusItem and NSPopover, replacing SwiftUI's MenuBarExtra
/// to enable programmatic popover toggling (for the global hotkey).
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let aggregator: StatusAggregator

    init(aggregator: StatusAggregator, popoverView: some View) {
        self.aggregator = aggregator

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.action = #selector(AppDelegate.togglePopover)
        statusItem.button?.image = NSImage(named: "status-ok")
        statusItem.button?.image?.isTemplate = true

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: popoverView)

        startObservingIcon()
    }

    func togglePopover() { 
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Uses `withObservationTracking` to reactively update the status bar icon
    /// whenever the aggregator's state changes.
    private func startObservingIcon() {
        withObservationTracking {
            let iconName = self.currentIconName()
            self.statusItem.button?.image = NSImage(named: iconName)
            self.statusItem.button?.image?.isTemplate = true
            self.statusItem.button?.setAccessibilityLabel(self.accessibilityStatusLabel())
        } onChange: {
            Task { @MainActor [weak self] in self?.startObservingIcon() }
        }
    }

    private func currentIconName() -> String {
        let (_, badgeCount) = aggregator.menuBarIcon()
        if badgeCount == 0 { return "status-ok" }
        if badgeCount <= 9 { return "status-\(badgeCount)" }
        return "status-10plus"
    }

    private func accessibilityStatusLabel() -> String {
        let (_, badgeCount) = aggregator.menuBarIcon()
        if badgeCount == 0 { return String(localized: "All builds passing") }
        return String(localized: "\(badgeCount) failing \(badgeCount == 1 ? "build" : "builds")")
    }
}
