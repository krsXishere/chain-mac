import CoreGraphics
import Foundation

// A key combination as the user means it, not as Carbon names it. The bindings
// themselves live here so that the Carbon layer stays a thin adapter and the
// whole default table is testable without event taps.
public struct KeyCombo: Hashable, Codable, Sendable, CustomStringConvertible {
    /// Carbon modifier mask: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
    public var modifiers: UInt32
    /// Carbon virtual key code. Layout independent: 0 is "A" on QWERTY and on
    /// AZERTY, which is what makes rebinding work on non-US keyboards.
    public var keyCode: UInt16

    public init(modifiers: UInt32, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    public var description: String {
        var parts: [String] = []
        if modifiers & 4096 != 0 { parts.append("⌃") }
        if modifiers & 2048 != 0 { parts.append("⌥") }
        if modifiers & 512 != 0 { parts.append("⇧") }
        if modifiers & 256 != 0 { parts.append("⌘") }
        parts.append(KeyCombo.name(for: keyCode))
        return parts.joined()
    }

    public static let control: UInt32 = 4096
    public static let option: UInt32 = 2048
    public static let shift: UInt32 = 512
    public static let command: UInt32 = 256
    public static let base = control | option

    /// Virtual key codes for the keys the default table uses. Values are from
    /// HIToolbox's Events.h and are stable across keyboard layouts.
    public enum Code {
        public static let h: UInt16 = 4, j: UInt16 = 38, k: UInt16 = 40, l: UInt16 = 37
        public static let leftArrow: UInt16 = 123, rightArrow: UInt16 = 124
        public static let downArrow: UInt16 = 125, upArrow: UInt16 = 126
        public static let r: UInt16 = 15, f: UInt16 = 3, c: UInt16 = 8, p: UInt16 = 35
        public static let n: UInt16 = 45, q: UInt16 = 12, t: UInt16 = 17
        public static let equal: UInt16 = 24, minus: UInt16 = 27, zero: UInt16 = 29
        public static let leftBracket: UInt16 = 33, rightBracket: UInt16 = 30
    }

    static func name(for keyCode: UInt16) -> String {
        switch keyCode {
        case Code.leftArrow: return "←"
        case Code.rightArrow: return "→"
        case Code.downArrow: return "↓"
        case Code.upArrow: return "↑"
        case Code.h: return "H"
        case Code.j: return "J"
        case Code.k: return "K"
        case Code.l: return "L"
        case Code.r: return "R"
        case Code.f: return "F"
        case Code.c: return "C"
        case Code.p: return "P"
        case Code.n: return "N"
        case Code.q: return "Q"
        case Code.t: return "T"
        case Code.equal: return "="
        case Code.minus: return "-"
        case Code.zero: return "0"
        case Code.leftBracket: return "["
        case Code.rightBracket: return "]"
        default: return "key\(keyCode)"
        }
    }
}

public enum StripAction: String, Codable, Sendable, CaseIterable {
    case focusLeft, focusRight, focusUp, focusDown
    case focusFirst, focusLast
    case moveLeft, moveRight, moveUp, moveDown
    case cycleWidth, fullWidth, center
    case wider, narrower, taller, shorter, equalHeights
    case stackLeft, stackRight, unstackRight, unstackLeft
    case toggleTabs, float, unfloat
    case pinLeft, pinRight
    case nextDisplay
    case quit

    public var isNavigating: Bool {
        switch self {
        case .focusLeft, .focusRight, .focusUp, .focusDown,
             .focusFirst, .focusLast,
             .moveLeft, .moveRight, .moveUp, .moveDown:
            return true
        default:
            return false
        }
    }
}

// Marked as a series of updates so that adding a default later cannot silently
// take a key the user has already rebound in their own mind.
public extension StripAction {
    var defaultCombos: [KeyCombo] {
        let base = KeyCombo.base
        let shift = base | KeyCombo.shift
        let cmd = base | KeyCombo.command

        switch self {
        case .focusLeft:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.leftArrow),
                    KeyCombo(modifiers: base, keyCode: KeyCombo.Code.h)]
        case .focusRight:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.rightArrow),
                    KeyCombo(modifiers: base, keyCode: KeyCombo.Code.l)]
        case .focusUp:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.upArrow),
                    KeyCombo(modifiers: base, keyCode: KeyCombo.Code.k)]
        case .focusDown:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.downArrow),
                    KeyCombo(modifiers: base, keyCode: KeyCombo.Code.j)]
        case .focusFirst:
            return [KeyCombo(modifiers: cmd, keyCode: KeyCombo.Code.leftArrow)]
        case .focusLast:
            return [KeyCombo(modifiers: cmd, keyCode: KeyCombo.Code.rightArrow)]
        case .moveLeft:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.leftArrow),
                    KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.h)]
        case .moveRight:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.rightArrow),
                    KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.l)]
        case .moveUp:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.upArrow),
                    KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.k)]
        case .moveDown:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.downArrow),
                    KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.j)]
        case .cycleWidth:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.r)]
        case .fullWidth:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.f)]
        case .center:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.c)]
        case .wider:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.equal)]
        case .narrower:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.minus)]
        case .taller:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.equal)]
        case .shorter:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.minus)]
        case .equalHeights:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.zero)]
        case .stackLeft:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.rightBracket)]
        case .stackRight:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.leftBracket)]
        case .unstackRight:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.rightBracket)]
        case .unstackLeft:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.leftBracket)]
        case .toggleTabs:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.t)]
        case .float:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.t)]
        case .unfloat:
            return []
        case .pinLeft:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.p)]
        case .pinRight:
            return [KeyCombo(modifiers: shift, keyCode: KeyCombo.Code.p)]
        case .nextDisplay:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.n)]
        case .quit:
            return [KeyCombo(modifiers: base, keyCode: KeyCombo.Code.q)]
        }
    }
}

// The whole binding table. Rules that make a settings UI honest:
// one combo drives at most one action, and an action may hold several combos.
public struct KeyBindings: Codable, Equatable, Sendable {
    public private(set) var combos: [StripAction: [KeyCombo]]

    public init(combos: [StripAction: [KeyCombo]] = [:]) {
        self.combos = combos
    }

    public static var defaults: KeyBindings {
        var table: [StripAction: [KeyCombo]] = [:]
        for action in StripAction.allCases {
            table[action] = action.defaultCombos
        }
        return KeyBindings(combos: table)
    }

    /// Why a combo cannot be assigned to `action`, or nil when it can.
    public func conflict(combo: KeyCombo, assigningTo action: StripAction) -> StripAction? {
        for (other, list) in combos where other != action && list.contains(combo) {
            return other
        }
        return nil
    }

    /// True when the combo was taken from another action, which is the only
    /// behaviour a user cannot misunderstand: the newer binding wins and the
    /// old one is reported by `conflict` before the change.
    @discardableResult
    public mutating func bind(_ combo: KeyCombo, to action: StripAction) -> StripAction? {
        let stealFrom = conflict(combo: combo, assigningTo: action)
        if let stealFrom {
            combos[stealFrom]?.removeAll { $0 == combo }
        }
        combos[action, default: []].append(combo)
        return stealFrom
    }

    @discardableResult
    public mutating func unbind(_ combo: KeyCombo, from action: StripAction) -> Bool {
        guard var list = combos[action], list.contains(combo) else { return false }
        list.removeAll { $0 == combo }
        combos[action] = list
        return true
    }

    public func action(for combo: KeyCombo) -> StripAction? {
        for (action, list) in combos where list.contains(combo) {
            return action
        }
        return nil
    }

    public mutating func resetShortcuts() {
        combos = KeyBindings.defaults.combos
    }

    /// Two actions sharing one combo is a bug in the table, not a user state,
    /// so it is checked at construction time in the tests rather than at runtime.
    public var duplicates: [KeyCombo] {
        var seen: Set<KeyCombo> = []
        var dupes: Set<KeyCombo> = []
        for list in combos.values {
            for combo in list {
                if !seen.insert(combo).inserted { dupes.insert(combo) }
            }
        }
        return dupes.sorted { String(describing: $0) < String(describing: $1) }
    }
}

public enum Presets {
    /// Resize ladder: 30% up to 80% in 10% steps, wrapping back to 30%. Full
    /// width is its own key (⌃⌥F), so it is not in this list.
    public static let defaultWidths: [CGFloat] = stride(from: 0.3, through: 0.8, by: 0.1).map { CGFloat($0) }

    /// Next preset above the current ratio, wrapping to the smallest. A current
    /// width that is not a preset steps to the first one that fits it.
    public static func next(after ratio: CGFloat, presets: [CGFloat] = defaultWidths) -> CGFloat {
        guard !presets.isEmpty else { return ratio }
        let sorted = presets.sorted()
        return sorted.first { $0 > ratio + 0.001 } ?? sorted[0]
    }

    public static func cycle(
        _ state: inout StripState,
        presets: [CGFloat] = defaultWidths,
        fits: (CGFloat) -> Bool = { _ in true }
    ) {
        let ring = state.scrolling
        guard !ring.isEmpty else { return }
        let index = ring.contains(state.focused) ? state.focused : ring[0]
        var ratio = next(after: state.columns[index].widthRatio, presets: presets)
        // A preset too wide for the space left after pinned columns is skipped,
        // never clamped: clamping would look like the key did nothing.
        var attempts = presets.count
        while !fits(ratio) && attempts > 0 {
            ratio = next(after: ratio, presets: presets)
            attempts -= 1
        }
        state.columns[index].widthRatio = ratio
    }
}
