import Foundation
import GRDB
@testable import PunchcardCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

private func defaultClient(_ db: PunchcardCore.Database) throws -> Client {
    try #require(ClientRepository(database: db).all().first { $0.name == "Default" })
}

private func entry(_ clientID: Int64, start: Date, end: Date?) -> Entry {
    Entry(clientID: clientID, startedAt: start, endedAt: end, createdAt: start, updatedAt: start)
}

@Suite struct MigrationTests {
    @Test func migrationsApplyToInMemoryDatabase() throws {
        let db = try PunchcardCore.Database.inMemory()
        let (version, names) = try db.queue.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA user_version"),
             try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"))
        }
        #expect(version == 1)
        #expect(names == [
            "clients", "entries", "settings",
            "entries_started_at", "entries_client_started", "entries_one_running",
        ])
    }

    @Test func seedsDefaultClient() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clients = try ClientRepository(database: db).all()
        #expect(clients.map(\.name) == ["Default"])
        #expect(clients[0].archivedAt == nil)
    }

    @Test func fileDatabaseUsesWALAndForeignKeysAndReopens() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("punchcard.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let first = try PunchcardCore.Database.open(at: url)
        let (mode, foreignKeys) = try first.queue.read { db in
            (try String.fetchOne(db, sql: "PRAGMA journal_mode"),
             try Bool.fetchOne(db, sql: "PRAGMA foreign_keys"))
        }
        #expect(mode == "wal")
        #expect(foreignKeys == true)

        // Reopening must not re-run migrations or re-seed.
        let second = try PunchcardCore.Database.open(at: url)
        #expect(try ClientRepository(database: second).all().count == 1)
    }

    @Test func refusesNewerDatabase() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        try DatabaseQueue(path: url.path).write { db in
            try db.execute(sql: "PRAGMA user_version = 99")
        }

        #expect(throws: DatabaseOpenError.newerSchema(found: 99, supported: 1)) {
            try PunchcardCore.Database.open(at: url)
        }
        let version = try DatabaseQueue(path: url.path).read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version")
        }
        #expect(version == 99)
    }
}

@Suite struct ClientRepositoryTests {
    @Test func duplicateNameDifferingInCaseThrows() throws {
        let clients = ClientRepository(database: try .inMemory())
        try clients.insert(name: "Acme", at: t0)
        #expect(throws: DatabaseError.self) { try clients.insert(name: "ACME", at: t0) }
    }

    @Test func blankNameThrows() throws {
        let clients = ClientRepository(database: try .inMemory())
        #expect(throws: DatabaseError.self) { try clients.insert(name: "  ", at: t0) }
    }

    @Test func deletingClientWithEntriesThrows() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clients = ClientRepository(database: db)
        let acme = try clients.insert(name: "Acme", at: t0)
        try EntryRepository(database: db).insert(entry(acme.id!, start: t0, end: t0 + 60))

        #expect(throws: DatabaseError.self) { try clients.delete(id: acme.id!) }
        #expect(try clients.find(id: acme.id!) != nil)
    }

    @Test func deletingEmptyClientSucceeds() throws {
        let clients = ClientRepository(database: try .inMemory())
        let acme = try clients.insert(name: "Acme", at: t0)
        try clients.delete(id: acme.id!)
        #expect(try clients.find(id: acme.id!) == nil)
    }

    @Test func archivedClientsAreHiddenByDefault() throws {
        let clients = ClientRepository(database: try .inMemory())
        var acme = try clients.insert(name: "acme", at: t0)
        acme.archivedAt = t0 + 10
        try clients.update(acme)

        #expect(try clients.all().map(\.name) == ["Default"])
        #expect(try clients.all(includeArchived: true).map(\.name) == ["acme", "Default"])
        #expect(try clients.find(id: acme.id!) == acme)
    }
}

@Suite struct EntryRepositoryTests {
    @Test func secondRunningEntryThrows() throws {
        let db = try PunchcardCore.Database.inMemory()
        let entries = EntryRepository(database: db)
        let client = try defaultClient(db)
        try entries.insert(entry(client.id!, start: t0, end: nil))

        #expect(throws: DatabaseError.self) {
            try entries.insert(entry(client.id!, start: t0 + 60, end: nil))
        }
    }

    @Test func endBeforeStartThrows() throws {
        let db = try PunchcardCore.Database.inMemory()
        let entries = EntryRepository(database: db)
        let client = try defaultClient(db)

        #expect(throws: DatabaseError.self) {
            try entries.insert(entry(client.id!, start: t0, end: t0 - 1))
        }
    }

    @Test func roundTripsWithNoteAndFindsRunning() throws {
        let db = try PunchcardCore.Database.inMemory()
        let entries = EntryRepository(database: db)
        let client = try defaultClient(db)
        var done = entry(client.id!, start: t0, end: t0 + 3600)
        done.note = "invoice prep"
        done = try entries.insert(done)
        var running = try entries.insert(entry(client.id!, start: t0 + 7200, end: nil))

        #expect(try entries.find(id: done.id!) == done)
        #expect(try entries.running() == running)

        running.endedAt = t0 + 7300
        try entries.update(running)
        #expect(try entries.running() == nil)

        try entries.delete(id: done.id!)
        #expect(try entries.find(id: done.id!) == nil)
    }

    @Test func timestampsAreStoredAsIntegerUnixSeconds() throws {
        let db = try PunchcardCore.Database.inMemory()
        let client = try defaultClient(db)
        let saved = try EntryRepository(database: db)
            .insert(entry(client.id!, start: t0, end: t0 + 90.7))
        #expect(saved.endedAt == t0 + 90)
        let row = try #require(try db.queue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT typeof(started_at) AS type, started_at, ended_at, is_running,
                       (SELECT typeof(created_at) FROM clients WHERE id = ?) AS client_type
                FROM entries WHERE id = ?
                """, arguments: [client.id, saved.id])
        })
        #expect(row["type"] == "integer")
        #expect(row["client_type"] == "integer")
        #expect(row["started_at"] == 1_760_000_000)
        #expect(row["ended_at"] == 1_760_000_090)
        #expect(row["is_running"] == 0)
    }

    @Test func overlappingIncludesPartialAndRunningEntries() throws {
        let db = try PunchcardCore.Database.inMemory()
        let entries = EntryRepository(database: db)
        let id = try defaultClient(db).id!
        let before = try entries.insert(entry(id, start: t0 - 200, end: t0 - 100))
        let straddling = try entries.insert(entry(id, start: t0 - 50, end: t0 + 50))
        let inside = try entries.insert(entry(id, start: t0 + 100, end: t0 + 200))
        let running = try entries.insert(entry(id, start: t0 + 900, end: nil))

        #expect(try entries.entries(overlapping: t0, t0 + 1000) == [straddling, inside, running])
        #expect(try entries.entries(overlapping: t0 - 300, t0 - 100) == [before])
    }
}

@Suite struct SettingsStoreTests {
    @Test func absentSettingsReturnDefaults() throws {
        let settings = SettingsStore(database: try .inMemory())
        #expect(try settings.weekStartDay == 1)
        #expect(try settings.idleThresholdSeconds == 600)
        #expect(try settings.menuBarStyle == .time)
        #expect(try settings.onboardedAt == nil)
    }

    @Test func settingsRoundTrip() throws {
        let settings = SettingsStore(database: try .inMemory())
        try settings.setWeekStartDay(7)
        try settings.setIdleThresholdSeconds(900)
        try settings.setMenuBarStyle(.icon)
        try settings.setOnboardedAt(t0)
        try settings.setWeekStartDay(3)

        #expect(try settings.weekStartDay == 3)
        #expect(try settings.idleThresholdSeconds == 900)
        #expect(try settings.menuBarStyle == .icon)
        #expect(try settings.onboardedAt == t0)
    }

    @Test func invalidStoredValuesReadAsDefaults() throws {
        let db = try PunchcardCore.Database.inMemory()
        try db.queue.write { db in
            try db.execute(sql: """
                INSERT INTO settings (key, value) VALUES
                  ('week_start_day', '9'), ('idle_threshold_seconds', 'soon'), ('menu_bar_style', 'neon')
                """)
        }
        let settings = SettingsStore(database: db)
        #expect(try settings.weekStartDay == 1)
        #expect(try settings.idleThresholdSeconds == 600)
        #expect(try settings.menuBarStyle == .time)
    }
}
