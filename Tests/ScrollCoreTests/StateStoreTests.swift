import XCTest
@testable import ScrollCore

final class StateStoreTests: XCTestCase {
    private func row(_ key: String, position: Int = 0, width: Double = 625) -> SavedWindow {
        SavedWindow(key: key, bundleID: "com.apple.finder", title: "Documents",
                    windowID: 42, position: position, width: width)
    }

    func testSavedWidthComesBackExactly() throws {
        let store = try StateStore(path: ":memory:")
        store.save([row("a", width: 625)])
        XCTAssertEqual(store.load()["a"]?.width, 625)
    }

    func testSavingAgainReplacesTheRowInsteadOfDuplicatingIt() throws {
        let store = try StateStore(path: ":memory:")
        store.save([row("a", position: 0, width: 625)])
        store.save([row("a", position: 2, width: 700)])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded["a"]?.position, 2)
        XCTAssertEqual(loaded["a"]?.width, 700)
    }

    func testRowsSurviveReopeningTheFile() throws {
        let path = NSTemporaryDirectory() + "chainmac-\(UUID().uuidString).sqlite"
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
        }
        do {
            let first = try StateStore(path: path)
            first.save([row("a", position: 1, width: 625)])
        }
        let second = try StateStore(path: path)
        XCTAssertEqual(second.load()["a"], row("a", position: 1, width: 625))
    }

    func testPruneDropsRowsOlderThanTheCutoffOnly() throws {
        let store = try StateStore(path: ":memory:")
        store.save([row("old")])
        store.prune(before: Date().addingTimeInterval(60))
        XCTAssertTrue(store.load().isEmpty)
        store.save([row("new")])
        store.prune(before: Date().addingTimeInterval(-60))
        XCTAssertEqual(Set(store.load().keys), ["new"])
    }

    func testRowSavedAfterPruneIsWrittenEvenIfItMatchedBefore() throws {
        let store = try StateStore(path: ":memory:")
        store.save([row("a")])
        store.prune(before: Date().addingTimeInterval(60))
        store.save([row("a")])
        XCTAssertEqual(store.load().count, 1)
    }
}
