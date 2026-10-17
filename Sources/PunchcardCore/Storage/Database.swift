import Foundation
import GRDB

/// The Punchcard SQLite database: one connection, opened with the shared pragmas and
/// migrated to the latest schema. See docs/schema.md for the data contract.
public final class Database: Sendable {
    let queue: DatabaseQueue

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try Migrator.migrate(queue)
    }

    /// Opens (creating if needed) the database file at `url` and migrates it.
    /// Throws `DatabaseOpenError.newerSchema` if a newer Punchcard wrote the file.
    public static func open(at url: URL) throws -> Database {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try Database(queue: DatabaseQueue(path: url.path, configuration: configuration()))
    }

    /// Opens a migrated, private in-memory database, for tests and previews.
    public static func inMemory() throws -> Database {
        try Database(queue: DatabaseQueue(configuration: configuration()))
    }

    /// `~/Library/Application Support/Punchcard/punchcard.sqlite`.
    public static func defaultURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Punchcard", isDirectory: true)
            .appendingPathComponent("punchcard.sqlite")
    }

    private static func configuration() -> Configuration {
        let busyTimeout: TimeInterval = 2
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(busyTimeout)
        config.prepareDatabase { db in
            // In-memory databases report "memory" and ignore the request.
            let deadline = Date(timeIntervalSinceNow: busyTimeout)
            while true {
                do {
                    try db.execute(sql: "PRAGMA journal_mode = WAL")
                    return
                } catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }
        return config
    }
}

public enum DatabaseOpenError: Error, Equatable, LocalizedError {
    /// The file's `user_version` is above the newest migration this build knows.
    case newerSchema(found: Int, supported: Int)

    public var errorDescription: String? {
        switch self {
        case .newerSchema:
            "This database was created by a newer version of Punchcard."
        }
    }
}
