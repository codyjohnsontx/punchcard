import Foundation
import GRDB

/// A client (or project) that time is tracked against. Names are unique ignoring case.
public struct Client: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64?
    public var name: String
    /// When the client was archived; nil while active.
    public var archivedAt: Date?
    public var createdAt: Date

    public init(id: Int64? = nil, name: String, archivedAt: Date? = nil, createdAt: Date) {
        self.id = id
        self.name = name
        self.archivedAt = archivedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case archivedAt = "archived_at"
        case createdAt = "created_at"
    }
}

/// One block of tracked time. `endedAt` is nil while the clock runs; at most one entry runs.
public struct Entry: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64?
    public var clientID: Int64
    public var startedAt: Date
    public var endedAt: Date?
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: Int64? = nil, clientID: Int64, startedAt: Date, endedAt: Date? = nil,
        note: String = "", createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.clientID = clientID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isRunning: Bool { endedAt == nil }

    enum CodingKeys: String, CodingKey {
        case id, note
        case clientID = "client_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// Timestamps are stored as integer Unix seconds (docs/schema.md).
extension Client: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clients"

    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .secondsSince1970
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSince1970
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension Entry: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "entries"

    public static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .secondsSince1970
    }

    public static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSince1970
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
