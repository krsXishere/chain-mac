import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// AX calls are synchronous IPC into another process and can block for
// milliseconds, so every read is bounded by a messaging timeout.
public struct AXWindowHandle: @unchecked Sendable {
    public let pid: pid_t
    public let element: AXUIElement
    public let title: String
    public let frame: CGRect
    /// CGWindowID, which is what grouping columns by app keys on.
    public let windowID: CGWindowID

    public init(
        pid: pid_t,
        element: AXUIElement,
        title: String,
        frame: CGRect,
        windowID: CGWindowID
    ) {
        self.pid = pid
        self.element = element
        self.title = title
        self.frame = frame
        self.windowID = windowID
    }

    public func setPosition(_ point: CGPoint) -> AXError {
        var value = point
        guard let raw = AXValueCreate(.cgPoint, &value) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, raw)
    }

    public func setSize(_ size: CGSize) -> AXError {
        var value = size
        guard let raw = AXValueCreate(.cgSize, &value) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, raw)
    }

    // Apps with a minimum size accept the attribute but end up with the wrong
    // frame, so a success code is not proof the window moved.
    public func currentFrame() -> CGRect? {
        AXBridge.frame(of: element)
    }

    /// Make this app frontmost so it gets the keyboard and the menu bar. The
    /// window itself is not raised: raising reorders the app's own windows above
    /// its neighbours and makes the strip flash.
    public func activateApp() {
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}

public enum AXBridge {

    public static let messagingTimeout: Float = 0.5

    public static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // Standard resizable windows of every regular app on the current Space.
    // Dialogs, sheets, panels and fullscreen windows are skipped: they float and
    // must never enter the strip. Background apps are included because the strip
    // spans the whole Space, not just the app you happen to be in.
    public static func tiledWindows(limit: Int = 64) -> [AXWindowHandle] {
        // AXWindows lists a window on every Space, so app order alone would splice
        // two desktops into one strip: pressing right on Space 2 would walk into a
        // window that is not on screen. CGWindowList only reports the windows the
        // window server has on the active Space, and that is the strip's boundary.
        let onScreen = onScreenWindowIDs()
        var handles: [AXWindowHandle] = []
        for app in NSWorkspace.shared.runningApplications where isStripApp(app) {
            guard handles.count < limit else { break }
            handles.append(contentsOf: windows(of: app, limit: limit - handles.count, onScreen: onScreen))
        }
        // The filter is an optimisation, not a rule: if it removed everything the
        // attribute is not readable here, and a strip of every window beats no
        // strip at all.
        guard handles.isEmpty else { return Array(handles.prefix(limit)) }
        for app in NSWorkspace.shared.runningApplications where isStripApp(app) {
            guard handles.count < limit else { break }
            handles.append(contentsOf: windows(of: app, limit: limit - handles.count))
        }
        return Array(handles.prefix(limit))
    }

    /// Window numbers the window server currently has on screen. Spaces it is not
    /// showing are absent, which is exactly the filter the strip needs.
    static func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        var ids: Set<CGWindowID> = []
        for info in list {
            guard let number = info[kCGWindowNumber as String] as? Int else { continue }
            ids.insert(CGWindowID(number))
        }
        return ids
    }

    /// Regular apps with a Dock presence. Accessory apps (menu bar utilities) and
    /// background daemons do not own tiled windows.
    static func isStripApp(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular, !app.isTerminated else { return false }
        // Our own windows are panels and overlays, never columns.
        return app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    static func windows(
        of app: NSRunningApplication,
        limit: Int,
        onScreen: Set<CGWindowID>? = nil
    ) -> [AXWindowHandle] {
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard let raw = copy(element, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return raw.compactMap { window -> AXWindowHandle? in
            guard isTiled(window), let frame = frame(of: window) else { return nil }
            // AXWindowNumber is not present on every app. A window without one can
            // still be tiled, so it falls back to a value derived from the element
            // rather than being dropped from the strip.
            let real = windowNumber(of: window)
            let number = real ?? fallbackWindowID(window)
            // Only a real window number can be matched against the window server.
            if let onScreen, let real, !onScreen.contains(real) { return nil }
            let title = copy(window, kAXTitleAttribute) as? String ?? ""
            return AXWindowHandle(
                pid: pid,
                element: window,
                title: title,
                frame: frame,
                windowID: number
            )
        }.prefix(limit).map { $0 }
    }

    /// AX exposes the CGWindowID of a window so the window server's idea of
    /// "visible right now" can be applied to it.
    /// Stable enough to group and compare within one run: a window keeps its
    /// element for as long as it exists.
    static func fallbackWindowID(_ element: AXUIElement) -> CGWindowID {
        // CFHash is derived from the element's identity inside the target app, so
        // two AXUIElement objects for the same window hash alike. The object's own
        // address would not: every AX query hands back a fresh wrapper.
        CGWindowID(truncatingIfNeeded: CFHash(element))
    }

    static func windowNumber(of element: AXUIElement) -> CGWindowID? {
        guard let raw = copy(element, "AXWindowNumber") else { return nil }
        // AX hands back a CFNumber, which does not bridge to Int with `as?`.
        guard CFGetTypeID(raw) == CFNumberGetTypeID() else { return nil }
        var value: Int32 = 0
        guard CFNumberGetValue((raw as! CFNumber), .sInt32Type, &value) else { return nil }
        return CGWindowID(value)
    }

    static func isTiled(_ element: AXUIElement) -> Bool {
        if (copy(element, kAXSubroleAttribute) as? String) != kAXStandardWindowSubrole {
            return false
        }
        if let modal = copy(element, "AXModal") as? Bool, modal { return false }
        if (copy(element, kAXMinimizedAttribute) as? Bool) != false { return false }
        // Native fullscreen gets its own Space and belongs to macOS.
        if (copy(element, "AXFullScreen") as? Bool) == true { return false }
        return true
    }

    public struct Diagnostics {
        public let apps: Int
        public let rawWindows: Int
        public let kept: Int
        public let failures: [String]
    }

    // Reports every candidate app, window and subrole, so a short strip can be
    // traced instead of guessed at.
    public static func diagnose() -> Diagnostics {
        var failures: [String] = []
        var apps = 0
        var raw = 0
        var kept = 0

        for app in NSWorkspace.shared.runningApplications where isStripApp(app) {
            apps += 1
            let pid = app.processIdentifier
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            guard let windows = copy(element, kAXWindowsAttribute) as? [AXUIElement] else {
                failures.append("\(app.localizedName ?? "?") \(pid): AXWindows unreadable")
                continue
            }
            raw += windows.count
            failures.append("\(app.localizedName ?? "?") \(pid): \(windows.count) raw")
            for (i, window) in windows.enumerated() {
                let subrole = copy(window, kAXSubroleAttribute) as? String ?? "nil"
                let title = copy(window, kAXTitleAttribute) as? String ?? ""
                let full = (copy(window, "AXFullScreen") as? Bool) == true
                let min = (copy(window, kAXMinimizedAttribute) as? Bool) == true
                failures.append("  \(i): subrole=\(subrole) full=\(full) min=\(min) title=\(title.prefix(24))")
                if isTiled(window) { kept += 1 }
            }
        }
        return Diagnostics(apps: apps, rawWindows: raw, kept: kept, failures: failures)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = point(element, kAXPositionAttribute),
              let size = size(element, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = copy(element, attribute) else { return nil }
        var value = CGPoint.zero
        return AXValueGetValue(raw as! AXValue, .cgPoint, &value) ? value : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw = copy(element, attribute) else { return nil }
        var value = CGSize.zero
        return AXValueGetValue(raw as! AXValue, .cgSize, &value) ? value : nil
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
