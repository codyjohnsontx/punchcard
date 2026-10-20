import Foundation
import GRDB

/// Adds, renames, archives, unarchives and deletes clients from the History window. Every
/// refusal, whether from the name rules or from the database, comes back as a
/// `ClientEditError` so the window always has a message to show.
public struct ClientEditor: Sendable {
    let database: Database
    let now: @Sendable () -> Date

    public init(database: Database, now: @escaping @Sendable () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    /// Adds an active client and returns it as stored (name normalized).
    @discardableResult
    public func add(name: String) throws -> Client {
        try mappingNameErrors {
            try ClientRepository(database: database).insert(name: name, at: now())
        }
    }

    /// Renames a client and returns it as stored. A name equal, ignoring case, to another
    /// client's is refused; the client can still change the case of its own name.
    @discardableResult
    public func rename(id: Int64, to name: String) throws -> Client {
        try mappingNameErrors {
            try database.queue.write { db in
                var client = try Self.fetch(id, db)
                client.name = try ClientRepository.validName(name, excluding: id, in: db)
                try client.update(db)
                return client
            }
        }
    }

    /// Archives a client, hiding it from the dropdown and the pickers while its entries stay in
    /// history. Refused for the only active client and while the client's clock runs; archiving
    /// an archived client changes nothing.
    @discardableResult
    public func archive(id: Int64) throws -> Client {
        let now = TimerEngine.wholeSeconds(now())
        return try database.queue.write { db in
            var client = try Self.fetch(id, db)
            guard client.archivedAt == nil else { return client }
            if try Self.isOnlyActive(client, db) { throw ClientEditError.archivingLastActive }
            if try EntryRepository.running(db)?.clientID == id { throw ClientEditError.running }
            client.archivedAt = now
            try client.update(db)
            return client
        }
    }

    /// Makes an archived client active again; unarchiving an active client changes nothing.
    @discardableResult
    public func unarchive(id: Int64) throws -> Client {
        try database.queue.write { db in
            var client = try Self.fetch(id, db)
            guard client.archivedAt != nil else { return client }
            client.archivedAt = nil
            try client.update(db)
            return client
        }
    }

    /// Deletes a client that has no entries. The only active client is refused, and one with
    /// entries is refused with the hint to archive it instead; deleting a client that is already
    /// gone is not an error.
    public func delete(id: Int64) throws {
        do {
            try database.queue.write { db in
                guard let client = try Client.fetchOne(db, key: id) else { return }
                if try Self.isOnlyActive(client, db) { throw ClientEditError.deletingLastActive }
                let count = try Int.fetchOne(
                    db, sql: "SELECT count(*) FROM entries WHERE client_id = ?", arguments: [id]) ?? 0
                guard count == 0 else { throw ClientEditError.hasEntries }
                _ = try Client.deleteOne(db, key: id)
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
            // The schema's ON DELETE RESTRICT backstop, should a write slip in between.
            throw ClientEditError.hasEntries
        }
    }

    private static func fetch(_ id: Int64, _ db: GRDB.Database) throws -> Client {
        guard let client = try Client.fetchOne(db, key: id) else { throw ClientEditError.missing }
        return client
    }

    private static func isOnlyActive(_ client: Client, _ db: GRDB.Database) throws -> Bool {
        guard client.archivedAt == nil else { return false }
        return try Client.filter(sql: "archived_at IS NULL").fetchCount(db) == 1
    }

    private func mappingNameErrors<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch ClientNameError.blank {
            throw ClientEditError.blank
        } catch ClientNameError.duplicate {
            throw ClientEditError.duplicate
        }
    }
}

public enum ClientEditError: Error, Equatable, LocalizedError {
    case blank
    case duplicate
    /// The client was deleted meanwhile.
    case missing
    /// Deleting a client that has entries; it can be archived instead.
    case hasEntries
    /// Archiving the client whose clock runs.
    case running
    /// Archiving the only active client, which would leave the dropdown without one.
    case archivingLastActive
    /// Deleting the only active client, which would leave the dropdown without one.
    case deletingLastActive

    public var errorDescription: String? {
        switch self {
        case .blank: "Enter a name."
        case .duplicate: "Another client already has this name."
        case .missing: "This client no longer exists."
        case .hasEntries: "This client has entries and can't be deleted. Archive it instead."
        case .running: "This client's clock is running. Stop it before archiving."
        case .archivingLastActive: "Add another client before archiving this one."
        case .deletingLastActive: "Add another client before deleting this one."
        }
    }
}
