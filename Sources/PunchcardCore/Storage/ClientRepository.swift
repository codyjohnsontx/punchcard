import Foundation
import GRDB

/// Reads and writes clients. Constraint violations (blank or case-insensitively duplicate
/// name, deleting a client that has entries) surface as thrown `DatabaseError`s.
public struct ClientRepository: Sendable {
    let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// All clients ordered by name, active ones only unless `includeArchived`.
    public func all(includeArchived: Bool = false) throws -> [Client] {
        try database.queue.read { db in
            var request = Client.order(sql: "name COLLATE NOCASE")
            if !includeArchived {
                request = request.filter(sql: "archived_at IS NULL")
            }
            return try request.fetchAll(db)
        }
    }

    public func find(id: Int64) throws -> Client? {
        try database.queue.read { db in try Client.fetchOne(db, key: id) }
    }

    /// Inserts a client and returns it as stored (timestamps truncated to whole seconds).
    @discardableResult
    public func insert(name: String, at date: Date = Date()) throws -> Client {
        try database.queue.write { db in
            try Client(name: name, createdAt: date).insertAndFetch(db)
        }
    }

    public func update(_ client: Client) throws {
        try database.queue.write { db in try client.update(db) }
    }

    /// Deletes a client. Throws if it has entries; archive it instead.
    public func delete(id: Int64) throws {
        try database.queue.write { db in _ = try Client.deleteOne(db, key: id) }
    }
}
