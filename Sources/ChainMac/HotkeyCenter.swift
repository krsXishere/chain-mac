import Carbon.HIToolbox
import Foundation
import ScrollCore

// Thin adapter over Carbon hot keys. Carbon is used rather than a CGEventTap so
// that the app does not need the Input Monitoring permission and cannot slow
// down unrelated keystrokes: the system delivers only the combinations we own.
@MainActor
final class HotkeyCenter {
    typealias Handler = (StripAction) -> Void

    private var refs: [EventHotKeyRef] = []
    private var byID: [UInt32: StripAction] = [:]
    private var onPress: Handler = { _ in }
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    /// Actions whose combination Carbon refused because another app owns it.
    private(set) var failures: [StripAction: OSStatus] = [:]

    private static let signature: OSType = 0x4348_4D43 // 'CHMC'

    func start(_ bindings: KeyBindings, onPress: @escaping Handler) {
        self.onPress = onPress
        installHandlerIfNeeded()
        apply(bindings)
    }

    /// Re-registering is the whole conflict story: Carbon refuses a combination
    /// another app already owns, and the refusal lands in `failures`.
    func apply(_ bindings: KeyBindings) {
        unregisterAll()
        failures = [:]
        for action in StripAction.allCases {
            for combo in bindings.combos[action] ?? [] {
                let id = nextID
                nextID += 1
                var ref: EventHotKeyRef?
                let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
                let status = RegisterEventHotKey(
                    UInt32(combo.keyCode),
                    combo.modifiers,
                    hotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &ref
                )
                if status == noErr, let ref {
                    refs.append(ref)
                    byID[id] = action
                } else {
                    failures[action] = status
                }
            }
        }
    }

    func stop() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func unregisterAll() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        byID.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                return MainActor.assumeIsolated {
                    guard let action = center.byID[id.id] else { return OSStatus(eventNotHandledErr) }
                    center.onPress(action)
                    return noErr
                }
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )
    }
}
