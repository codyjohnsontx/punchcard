import Foundation
import GRDB

/// Reads and writes time entries. The schema rejects a second running entry and an entry
/// that ends before it starts; both surface as thrown `DatabaseError`s.
public struct EntryRepository: Sendable {
    let database: Database

    public init(database: Database) {
        self.database = database
    }

    public func find(id: Int64) throws -> Entry? {
        try database.queue.read { db in try Entry.fetchOne(db, key: id) }
    }

    /// The running entry, if any.
    public func running() throws -> Entry? {
        try database.queue.read { db in
            try Entry.filter(sql: "ended_at IS NULL").fetchOne(db)
        }
    }

    /// Entries that overlap `[start, end)`, oldest first. A running entry counts as
    /// extending to the present, so it overlaps any interval ending after its start.
    public func entries(overlapping start: Date, _ end: Date) throws -> [Entry] {
        try database.queue.read { db in
            try Entry
                .filter(sql: "started_at < ? AND (ended_at IS NULL OR ended_at > ?)",
                        arguments: [Int64(end.timeIntervalSince1970), Int64(start.timeIntervalSince1970)])
                .order(sql: "started_at, id")
                .fetchAll(db)
        }
    }

    /// Inserts an entry and returns it as stored (timestamps truncated to whole seconds).
    @discardableResult
    public func insert(_ entry: Entry) throws -> Entry {
        try database.queue.write { db in try entry.insertAndFetch(db) }
    }

    public func update(_ entry: Entry) throws {
        try database.queue.write { db in try entry.update(db) }
    }

    public func delete(id: Int64) throws {
        try database.queue.write { db in _ = try Entry.deleteOne(db, key: id) }
    }
}
