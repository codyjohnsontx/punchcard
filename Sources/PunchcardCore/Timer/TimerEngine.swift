import Foundation
import GRDB

/// Starts and stops the clock. One entry runs at a time: starting a client while another
/// runs ends the running entry and starts the new one at the same instant, in one
/// transaction. Every mutation takes its instant from `at`, or from the injected `now`.
public struct TimerEngine: Sendable {
    let database: Database
    let now: @Sendable () -> Date

    public init(database: Database, now: @escaping @Sendable () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    /// The running entry, if any.
    public func running() throws -> Entry? {
        try EntryRepository(database: database).running()
    }

    /// Starts the clock for `clientID`, ending any running entry at the same instant, and
    /// returns the running entry. Starting the client that already runs changes nothing.
    @discardableResult
    public func start(clientID: Int64, at date: Date? = nil) throws -> Entry {
        let date = Self.wholeSeconds(date ?? now())
        return try database.queue.write { db in
            var date = date
            if let running = try EntryRepository.running(db) {
                if running.clientID == clientID { return running }
                date = try Self.end(running, at: date, db).endedAt ?? date
            }
            return try Entry(clientID: clientID, startedAt: date, createdAt: date, updatedAt: date)
                .insertAndFetch(db)
        }
    }

    /// Stops the clock and returns the entry it ended, or nil when nothing was running.
    @discardableResult
    public func stop(at date: Date? = nil) throws -> Entry? {
        let date = Self.wholeSeconds(date ?? now())
        return try database.queue.write { db in
            guard let running = try EntryRepository.running(db) else { return nil }
            return try Self.end(running, at: date, db)
        }
    }

    private static func end(_ entry: Entry, at date: Date, _ db: GRDB.Database) throws -> Entry {
        let date = max(date, entry.startedAt)
        var entry = entry
        entry.endedAt = date
        entry.updatedAt = date
        try entry.update(db)
        return entry
    }

    /// The database stores whole seconds; truncating first keeps the returned entries equal
    /// to what is stored and makes the previous entry's end equal the next one's start.
    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}
