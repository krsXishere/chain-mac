import CoreGraphics
import Foundation
import ScrollCore

// Horizontal scroll as a way to move through the strip. Unlike HotkeyCenter this
// needs an event tap, so it needs the Input Monitoring permission, and a tap that
// dies silently takes scrolling with it. Three rules keep the blast radius small:
//
// 1. Only scroll-wheel events with no phase are looked at; a gesture that belongs
//    to an app (momentum, trackpad swipe) is passed through untouched.
// 2. An event is consumed only when the modifier is down AND the horizontal delta
//    is the larger of the two. Everything else returns the event untouched.
// 3. Every failure path re-enables or disables the tap and reports it, so the worst
//    case is "scrolling works and the strip does not move", never a frozen wheel.
@MainActor
final class ScrollCenter {
    typealias Handler = (StripAction) -> Void

    /// Pixels of horizontal travel per focus step. A Magic Mouse reports a few
    /// pixels per notch, a trackpad far more per gesture.
    private static let stepThreshold: Int64 = 12
    private static let cooldown: TimeInterval = 0.12

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var onScroll: Handler = { _ in }
    private var lastStep = Date.distantPast
    private var carry: Int64 = 0

    /// Set when the tap could not be created, which is what happens without the
    /// Input Monitoring grant. The menu reports this instead of failing silently.
    private(set) var failure: String?

    var isRunning: Bool { tap != nil }

    func start(onScroll: @escaping Handler) {
        self.onScroll = onScroll
        failure = nil
        guard tap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let center = Unmanaged<ScrollCenter>.fromOpaque(userData).takeUnretainedValue()

                // A tap disabled by the system has to be switched back on here, or
                // it stays dead until the app restarts.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { center.reenable() }
                    return Unmanaged.passUnretained(event)
                }

                let consumed = MainActor.assumeIsolated {
                    center.handle(event)
                }
                // A listen-only tap cannot really swallow the event; returning nil
                // is how it asks the system to drop it, and is harmless otherwise.
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            failure = "Input Monitoring not granted"
            return
        }

        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: true)

        if !CGPreflightListenEventAccess() {
            failure = "Input Monitoring not granted"
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let source { CFMachPortInvalidate(tap!) }
        _ = source
        tap = nil
        source = nil
    }

    private func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// True means "consume this event": the strip moved, the app under the cursor
    /// must not also scroll.
    private func handle(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 1 else {
            return false
        }
        let flags = event.flags
        guard flags.contains(.maskControl), flags.contains(.maskAlternate) else {
            carry = 0
            return false
        }

        let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        guard dx != 0, abs(dx) >= abs(dy) else { return false }

        let now = Date()
        guard now.timeIntervalSince(lastStep) >= Self.cooldown else { return true }

        carry += dx
        guard abs(carry) >= Self.stepThreshold else { return true }

        let action: StripAction = carry > 0 ? .focusRight : .focusLeft
        carry = 0
        lastStep = now
        onScroll(action)
        return true
    }
}
