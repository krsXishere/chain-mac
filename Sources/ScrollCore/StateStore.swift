import Foundation
import SQLite3

/// What the strip remembers about one window between runs and Space switches.
public struct SavedWindow: Equatable, Sendable {
    /// `bundleID#windowID`: stable while the window lives, even across a restart
    /// of ChainMac, which is what the width has to survive.
    public var key: String
    public var bundleID: String
    public var title: String
    public var windowID: UInt32
    /// Column index in the strip it was last laid out in.
    public var position: Int
    /// Width in points as the strip last laid it out, not as a ratio: a window
    /// that was 625 wide stays 625 wide.
    public var width: Double

    public init(
        key: String,
        bundleID: String,
        title: String,
        windowID: UInt32,
        position: Int,
        width: Double
    ) {
        self.key = key
        self.bundleID = bundleID
        self.title = title
        self.windowID = windowID
        self.position = position
        self.width = width
    }
}

public enum StateStoreError: Error, Equatable, Sendable {
    case open(String)
    case exec(String)
}

// One table, keyed by window. macOS has no public Space identifier, so a Space is
// not a column: each Space's strip is rebuilt from the windows it shows and
// ordered by `position`, which keeps every Space's own order without needing to
// know which Space is which.
public final class StateStore {
    private var db: OpaquePointer?
    /// Rows already on disk, so a key press that changes nothing writes nothing.
    private var lastSaved: [String: SavedWindow] = [:]

    private static let schema = """
        CREATE TABLE IF NOT EXISTS windows (
            key TEXT PRIMARY KEY,
            bundle_id TEXT NOT NULL,
            title TEXT NOT NULL,
            window_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            width REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """

    public init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open failed"
            sqlite3_close(handle)
            throw StateStoreError.open(message)
        }
        db = handle
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA synchronous=NORMAL")
        try exec(Self.schema)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    /// `~/Library/Application Support/ChainMac/state.sqlite`. Rows written before
    /// the last boot are dropped: window numbers restart at boot, so they could
    /// only ever match the wrong window.
    public static func openDefault() -> StateStore? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("ChainMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let store = try? StateStore(path: dir.appendingPathComponent("state.sqlite").path) else {
            return nil
        }
        if let boot = bootDate() { store.prune(before: boot) }
        return store
    }

    public static func bootDate() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
    }

    public func load() -> [String: SavedWindow] {
        var rows: [String: SavedWindow] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT key, bundle_id, title, window_id, position, width FROM windows"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return rows }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let key = Self.text(stmt, 0)
            rows[key] = SavedWindow(
                key: key,
                bundleID: Self.text(stmt, 1),
                title: Self.text(stmt, 2),
                windowID: UInt32(truncatingIfNeeded: sqlite3_column_int64(stmt, 3)),
                position: Int(sqlite3_column_int64(stmt, 4)),
                width: sqlite3_column_double(stmt, 5)
            )
        }
        return rows
    }

    /// Upserts only the rows that differ from what is already stored.
    @discardableResult
    public func save(_ rows: [SavedWindow]) -> Bool {
        let changed = rows.filter { lastSaved[$0.key] != $0 }
        guard !changed.isEmpty else { return true }
        let sql = """
            INSERT INTO windows (key, bundle_id, title, window_id, position, width, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            ON CONFLICT(key) DO UPDATE SET
                bundle_id = excluded.bundle_id,
                title = excluded.title,
                window_id = excluded.window_id,
                position = excluded.position,
                width = excluded.width,
                updated_at = excluded.updated_at
            """
        // SQLITE_TRANSIENT is a macro Swift does not import.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        do {
            try exec("BEGIN")
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StateStoreError.exec(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            let now = Date().timeIntervalSince1970
            for row in changed {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, row.key, -1, transient)
                sqlite3_bind_text(stmt, 2, row.bundleID, -1, transient)
                sqlite3_bind_text(stmt, 3, row.title, -1, transient)
                sqlite3_bind_int64(stmt, 4, Int64(row.windowID))
                sqlite3_bind_int64(stmt, 5, Int64(row.position))
                sqlite3_bind_double(stmt, 6, row.width)
                sqlite3_bind_double(stmt, 7, now)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw StateStoreError.exec(String(cString: sqlite3_errmsg(db)))
                }
            }
            try exec("COMMIT")
        } catch {
            _ = try? exec("ROLLBACK")
            return false
        }
        for row in changed { lastSaved[row.key] = row }
        return true
    }

    @discardableResult
    public func prune(before date: Date) -> Bool {
        lastSaved = [:]
        return (try? exec("DELETE FROM windows WHERE updated_at < \(date.timeIntervalSince1970)")) != nil
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw StateStoreError.exec(message)
        }
    }

    private static func text(_ stmt: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }
}
