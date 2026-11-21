import AppKit
import ScrollCore

// Menu bar shell. The app is LSUIElement so it has no Dock icon and no main
// window; the status item and the hotkeys are the only surfaces.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let controller = StripController()
    private let hotkeys = HotkeyCenter()
    private let scroll = ScrollCenter()
    private let bindings = KeyBindings.defaults
    private var layoutFailures: [StripAction: OSStatus] = [:]
    private var animateItem: NSMenuItem?

    @objc private func toggleAnimation() {
        controller.isAnimated.toggle()
        animateItem?.state = controller.isAnimated ? .on : .off
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The app icon, not a word. Template mode would turn it into a flat
        // silhouette (the plate and the bracket merge into one blob), which is why
        // the status item shows the real colours at a reduced size instead.
        if let icon = NSImage(named: "AppIcon") {
            icon.size = NSSize(width: 18, height: 18)
            item.button?.image = icon
            item.button?.imageScaling = .scaleProportionallyDown
        } else {
            item.button?.title = "ChainMac"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Tile frontmost app", action: #selector(tileNow), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Diagnostics", action: #selector(showDiagnostics), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Shortcut conflicts", action: #selector(showConflicts), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Scroll status", action: #selector(showScroll), keyEquivalent: ""))
        menu.addItem(.separator())
        let animate = NSMenuItem(title: "Animate moves", action: #selector(toggleAnimation), keyEquivalent: "")
        animate.state = controller.isAnimated ? .on : .off
        animateItem = animate
        menu.addItem(animate)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Grant Accessibility", action: #selector(grantAccess), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        let minimap = Minimap()
        controller.onMinimap = { ratios, focused in
            minimap.show(ratios: ratios, focused: focused)
        }

        if AXBridge.isTrusted() {
            startHotkeys()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appActivated() {
        // A Space switch looks like an app switch from here, and it is the only
        // signal macOS gives without private APIs. Rebuilding the strip first keeps
        // navigation inside the desktop the user is actually looking at.
        controller.syncToCurrentSpace()
        controller.followFrontmost()
    }

    private func startHotkeys() {
        hotkeys.start(bindings) { [weak self] action in
            self?.controller.perform(action)
        }
        // Horizontal scroll is optional and needs its own permission, so a failure
        // here never blocks the hotkeys.
        scroll.start { [weak self] action in
            self?.controller.perform(action)
        }
        layoutFailures = hotkeys.failures
        if !layoutFailures.isEmpty {
            // Not a dialog: a key that macOS reserved is a normal state on a
            // fresh install and should not interrupt the first launch.
            statusItem?.button?.toolTip = "ChainMac: some shortcuts are taken"
        }
    }

    @objc private func showConflicts() {
        guard !layoutFailures.isEmpty else {
            report("No conflicts: every default shortcut is free.")
            return
        }
        let lines = layoutFailures.map { action, status in
            "  \(action.rawValue): OSStatus \(status)"
        }
        report("These keys are taken by macOS or another app:\n\(lines.joined(separator: "\n"))")
    }

    @objc private func showScroll() {
        if let failure = scroll.failure {
            report("Horizontal scroll off: \(failure).\nGrant Input Monitoring to ChainMac, then restart it.")
            return
        }
        report("Horizontal scroll on. Hold ⌃⌥ and scroll sideways.")
    }

    @objc private func grantAccess() {
        // Never short-circuit on isTrusted: macOS caches the answer for the life of
        // the process, so a permission revoked in System Settings still reads as
        // granted here. Asking again is the only way to get a fresh prompt.
        guard !AXBridge.requestTrust() else {
            report("Accessibility granted. Restart ChainMac if the keys do nothing.")
            return
        }
        report("Waiting for Accessibility. Turn ChainMac on in System Settings, then restart the app.")
    }

    @objc private func tileNow() {
        guard AXBridge.isTrusted() else {
            report("Accessibility not granted. Use the menu item above.")
            return
        }
        guard controller.refresh() > 0 else {
            // An empty strip is a normal state (no regular app open), not a fault
            // worth a modal. The menu item below still prints the full diagnostic.
            statusItem?.button?.toolTip = "ChainMac: no tiled windows here"
            return
        }
        startHotkeys()
        report("Tiled \(controller.windowCount) windows.\n⌃⌥← → move focus, ⌃⌥P pins.")
    }

    @objc private func showDiagnostics() {
        report(diagnose())
    }

    private func diagnose() -> String {
        let d = AXBridge.diagnose()
        var lines = [
            "trusted=\(AXBridge.isTrusted()) raw=\(d.rawWindows) kept=\(d.kept)",
            "canvas=\(String(describing: StripController.canvas(for: NSScreen.main)))",
            "columns=\(controller.windowCount) focused=\(controller.state.focused)",
            "pinned left=\(controller.state.pinnedLeft) right=\(controller.state.pinnedRight)",
        ]
        lines.append(contentsOf: d.failures)
        lines.append("--- trace ---")
        lines.append(contentsOf: controller.trace)
        return lines.joined(separator: "\n")
    }

    private func report(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
