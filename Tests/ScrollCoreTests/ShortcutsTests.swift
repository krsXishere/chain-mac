import XCTest
@testable import ScrollCore

// The default table is a product promise: the site publishes exactly these keys.
// If one of them changes here, the PRD and the docs are wrong.
final class ShortcutsTests: XCTestCase {
    let table = KeyBindings.defaults

    func testBaseIsControlOptionNotPlainOption() {
        XCTAssertEqual(KeyCombo.base, 4096 | 2048)
        // Plain ⌥ is left to macOS for word jumps and special characters.
        let plainOption = KeyCombo(modifiers: KeyCombo.option, keyCode: KeyCombo.Code.h)
        XCTAssertNil(table.action(for: plainOption))
    }

    func testEveryPublishedDefaultIsBound() {
        let expected: [StripAction: [KeyCombo]] = [
            .focusLeft: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.leftArrow),
                         KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.h)],
            .focusRight: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.rightArrow),
                          KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.l)],
            .moveLeft: [KeyCombo(modifiers: KeyCombo.base | KeyCombo.shift, keyCode: KeyCombo.Code.leftArrow),
                        KeyCombo(modifiers: KeyCombo.base | KeyCombo.shift, keyCode: KeyCombo.Code.h),
                        KeyCombo(modifiers: KeyCombo.option | KeyCombo.command, keyCode: KeyCombo.Code.leftArrow)],
            .moveRight: [KeyCombo(modifiers: KeyCombo.base | KeyCombo.shift, keyCode: KeyCombo.Code.rightArrow),
                         KeyCombo(modifiers: KeyCombo.base | KeyCombo.shift, keyCode: KeyCombo.Code.l),
                         KeyCombo(modifiers: KeyCombo.option | KeyCombo.command, keyCode: KeyCombo.Code.rightArrow)],
            .arrange1: [KeyCombo(modifiers: KeyCombo.option | KeyCombo.command, keyCode: KeyCombo.Code.one)],
            .arrange2: [KeyCombo(modifiers: KeyCombo.option | KeyCombo.command, keyCode: KeyCombo.Code.two)],
            .arrange3: [KeyCombo(modifiers: KeyCombo.option | KeyCombo.command, keyCode: KeyCombo.Code.three)],
            .cycleWidth: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.r)],
            .fullWidth: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.f)],
            .center: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.c)],
            .pinLeft: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.p)],
            .pinRight: [KeyCombo(modifiers: KeyCombo.base | KeyCombo.shift, keyCode: KeyCombo.Code.p)],
            .toggleTabs: [KeyCombo(modifiers: KeyCombo.base | KeyCombo.shift, keyCode: KeyCombo.Code.t)],
            .float: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.t)],
            .nextDisplay: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.n)],
            .quit: [KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.q)],
        ]
        for (action, combos) in expected {
            XCTAssertEqual(table.combos[action], combos, "\(action) default changed")
        }
    }

    func testNoComboDrivesTwoActions() {
        XCTAssertEqual(table.duplicates, [], "default table has a conflicting combo")
    }

    func testDefaultTableCoversEveryNavigableAction() {
        for action in StripAction.allCases where action.isNavigating {
            XCTAssertFalse(action.defaultCombos.isEmpty, "\(action) has no default key")
        }
    }

    func testBindingStealsTheComboFromTheOtherAction() {
        var t = table
        let combo = KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.r)
        let victim = t.bind(combo, to: .center)
        XCTAssertEqual(victim, .cycleWidth)
        XCTAssertEqual(t.action(for: combo), .center)
        XCTAssertFalse(t.combos[.cycleWidth]!.contains(combo))
    }

    func testOneActionCanHoldSeveralCombos() {
        var t = KeyBindings()
        let a = KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.h)
        let b = KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.leftArrow)
        t.bind(a, to: .focusLeft)
        t.bind(b, to: .focusLeft)
        XCTAssertEqual(t.combos[.focusLeft], [a, b])
    }

    func testUnbindRemovesOnlyThatCombo() {
        var t = table
        let h = KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.h)
        XCTAssertTrue(t.unbind(h, from: .focusLeft))
        XCTAssertEqual(t.combos[.focusLeft]?.count, 1)
        XCTAssertEqual(t.action(for: h), nil)
    }

    func testResetRestoresTheDefaults() {
        var t = table
        t.bind(KeyCombo(modifiers: KeyCombo.base, keyCode: KeyCombo.Code.r), to: .center)
        t.resetShortcuts()
        XCTAssertEqual(t.combos, KeyBindings.defaults.combos)
        XCTAssertEqual(t.duplicates, [])
    }

    func testComboDescribesItselfWithSymbolsInAppleOrder() {
        let combo = KeyCombo(modifiers: KeyCombo.base | KeyCombo.shift, keyCode: KeyCombo.Code.p)
        XCTAssertEqual(combo.description, "⌃⌥⇧P")
    }

    func testArrangeCombosDescribeThemselves() {
        XCTAssertEqual(KeyBindings.defaults.combos[.arrange2]?.first?.description, "⌥⌘2")
        XCTAssertEqual(KeyBindings.defaults.combos[.moveRight]?.last?.description, "⌥⌘→")
    }

    // MARK: - Presets

    func testCycleWalksThePresetsAndWraps() {
        XCTAssertEqual(Presets.next(after: 0.3), 0.4, accuracy: 0.0001)
        XCTAssertEqual(Presets.next(after: 0.8), 0.3, accuracy: 0.0001)
    }

    func testCycleFromANonPresetWidthStepsToTheFirstLarger() {
        XCTAssertEqual(Presets.next(after: 0.45), 0.5, accuracy: 0.0001)
    }

    func testPresetLadderIsThirtyToEightyByTen() {
        XCTAssertEqual(Presets.defaultWidths.count, 6)
        XCTAssertEqual(Presets.defaultWidths.first!, 0.3, accuracy: 0.0001)
        XCTAssertEqual(Presets.defaultWidths.last!, 0.8, accuracy: 0.0001)
    }

    func testCycleSkipsPresetsThatDoNotFit() {
        var s = StripState(columns: [ColumnState(windowIDs: [], widthRatio: 0.3)], focused: 0)
        Presets.cycle(&s, fits: { $0 <= 0.5 })
        XCTAssertEqual(s.columns[0].widthRatio, 0.4, accuracy: 0.0001)
        Presets.cycle(&s, fits: { $0 <= 0.5 })
        XCTAssertEqual(s.columns[0].widthRatio, 0.5, accuracy: 0.0001)
        Presets.cycle(&s, fits: { $0 <= 0.5 })
        XCTAssertEqual(s.columns[0].widthRatio, 0.3, accuracy: 0.0001)
    }

    func testCycleLeavesPinnedColumnWidthAlone() {
        var s = StripState(
            columns: [ColumnState(windowIDs: [], widthRatio: 0.3),
                      ColumnState(windowIDs: [], widthRatio: 0.5)],
            focused: 1
        )
        try? s.pin(.left, at: 0)   // column 0 is pinned, so it is not in the ring
        XCTAssertEqual(s.scrolling, [1])
        Presets.cycle(&s)
        XCTAssertEqual(s.columns[0].widthRatio, 0.3, accuracy: 0.0001)
        XCTAssertEqual(s.columns[1].widthRatio, 0.6, accuracy: 0.0001)   // 0.5 -> 0.6
    }
}
