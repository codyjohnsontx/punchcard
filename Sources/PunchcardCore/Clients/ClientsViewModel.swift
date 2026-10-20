import Foundation
import GRDB

/// The rows of the Clients tab: every client, active ones first, each with its entry count
/// and whether its clock runs, which is what decides the actions the tab offers for it.
public struct ClientsViewModel: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public let id: Int64
        public let client: Client
        public let entryCount: Int
        /// The client's clock runs, so it cannot be archived.
        public let isRunning: Bool

        public var name: String { client.name }
        public var isArchived: Bool { client.archivedAt != nil }
        /// Only a client without entries can be deleted; one with entries is archived instead.
        public var canDelete: Bool { entryCount == 0 }
        public var canArchive: Bool { !isArchived && !isRunning }
        /// The client has entries and is still active, so archiving is what the tab suggests in
        /// place of deleting.
        public var suggestsArchive: Bool { !canDelete && !isArchived }
    }

    /// Active clients by name, then archived clients by name.
    public let rows: [Row]

    public init(clients: [Client], entryCounts: [Int64: Int], runningClientID: Int64?) {
        let rows = clients.compactMap { client in
            client.id.map { id in
                Row(id: id, client: client, entryCount: entryCounts[id] ?? 0, isRunning: runningClientID == id)
            }
        }
        let byName = { (a: Row, b: Row) in a.name.localizedStandardCompare(b.name) == .orderedAscending }
        self.rows = rows.filter { !$0.isArchived }.sorted(by: byName) + rows.filter(\.isArchived).sorted(by: byName)
    }

    public var activeCount: Int { rows.filter { !$0.isArchived }.count }

    public func row(id: Int64) -> Row? {
        rows.first { $0.id == id }
    }

    /// Reads every client, its entry count and the running entry in one transaction.
    public static func load(from database: Database) throws -> ClientsViewModel {
        try database.queue.read { db in
            let counts = try GRDB.Row.fetchAll(db, sql: "SELECT client_id, count(*) AS n FROM entries GROUP BY client_id")
            return ClientsViewModel(
                clients: try ClientRepository.all(includeArchived: true, db),
                entryCounts: Dictionary(uniqueKeysWithValues: counts.map { ($0["client_id"] as Int64, $0["n"] as Int) }),
                runningClientID: try EntryRepository.running(db)?.clientID)
        }
    }
}
