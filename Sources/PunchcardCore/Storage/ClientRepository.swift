import Foundation
import GRDB

/// Reads and writes clients. Names are normalized before writing and a blank or duplicate name
/// throws `ClientNameError` (docs/schema.md). Deleting a client that has entries throws a
/// `DatabaseError`.
public struct ClientRepository: Sendable {
    let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// All clients ordered by name, active ones only unless `includeArchived`.
    public func all(includeArchived: Bool = false) throws -> [Client] {
        try database.queue.read { db in
            var request = Client.all()
            if !includeArchived {
                request = request.filter(sql: "archived_at IS NULL")
            }
            return try request.fetchAll(db)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    public func find(id: Int64) throws -> Client? {
        try database.queue.read { db in try Client.fetchOne(db, key: id) }
    }

    /// Inserts a client and returns it as stored (name normalized, timestamps truncated to
    /// whole seconds).
    @discardableResult
    public func insert(name: String, at date: Date = Date()) throws -> Client {
        try database.queue.write { db in
            let name = try Self.validName(name, excluding: nil, in: db)
            return try Client(name: name, createdAt: date).insertAndFetch(db)
        }
    }

    /// Updates a client and returns it as stored (name normalized).
    @discardableResult
    public func update(_ client: Client) throws -> Client {
        try database.queue.write { db in
            var client = client
            client.name = try Self.validName(client.name, excluding: client.id, in: db)
            try client.update(db)
            return client
        }
    }

    /// Deletes a client. Throws if it has entries; archive it instead.
    public func delete(id: Int64) throws {
        try database.queue.write { db in _ = try Client.deleteOne(db, key: id) }
    }

    /// Trims Unicode whitespace and newlines, NFC-normalizes, and refuses a blank name or one
    /// equal ignoring case to another client's name.
    private static func validName(_ name: String, excluding id: Int64?, in db: GRDB.Database) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty else { throw ClientNameError.blank }
        let others = try String.fetchAll(db, sql: "SELECT name FROM clients WHERE id IS NOT ?", arguments: [id])
        guard !others.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ClientNameError.duplicate
        }
        return name
    }
}

public enum ClientNameError: Error, Equatable {
    case blank
    case duplicate
}
