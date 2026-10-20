import Foundation
@testable import PunchcardCore
import Testing

private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

private func entry(_ clientID: Int64, start: Date, end: Date?) -> Entry {
    Entry(clientID: clientID, startedAt: start, endedAt: end, createdAt: start, updatedAt: start)
}

private func editor(_ db: PunchcardCore.Database, now: Date = t0 + 100) -> ClientEditor {
    ClientEditor(database: db, now: { now })
}

@Suite struct ClientEditorTests {
    @Test func addsAClientWithANormalizedName() throws {
        let db = try PunchcardCore.Database.inMemory()
        let acme = try editor(db).add(name: " Acme\n")
        #expect(acme.name == "Acme")
        #expect(acme.archivedAt == nil)
        #expect(acme.createdAt == t0 + 100)
        #expect(try ClientRepository(database: db).all().map(\.name) == ["Acme", "Default"])
    }

    @Test(arguments: ["", "  ", "\u{A0}"])
    func addingABlankNameIsRefused(name: String) throws {
        let db = try PunchcardCore.Database.inMemory()
        #expect(throws: ClientEditError.blank) { try editor(db).add(name: name) }
        #expect(ClientEditError.blank.errorDescription == "Enter a name.")
    }

    @Test func addingAnExistingNameInDifferentCaseIsRefused() throws {
        let db = try PunchcardCore.Database.inMemory()
        try editor(db).add(name: "Acme")
        #expect(throws: ClientEditError.duplicate) { try editor(db).add(name: "ACME") }
        #expect(throws: ClientEditError.duplicate) { try editor(db).add(name: "default") }
        #expect(try ClientRepository(database: db).all().count == 2)
    }

    @Test func renamingToAnExistingNameInDifferentCaseIsRefused() throws {
        let db = try PunchcardCore.Database.inMemory()
        let acme = try editor(db).add(name: "Acme")
        try editor(db).add(name: "Globex")

        #expect(throws: ClientEditError.duplicate) { try editor(db).rename(id: acme.id!, to: "gLOBEX") }
        #expect(throws: ClientEditError.duplicate) { try editor(db).rename(id: acme.id!, to: " DEFAULT ") }
        #expect(try ClientRepository(database: db).find(id: acme.id!)?.name == "Acme")
        #expect(ClientEditError.duplicate.errorDescription == "Another client already has this name.")
    }

    @Test func renamesAClientAndKeepsItsOwnNameInNewCase() throws {
        let db = try PunchcardCore.Database.inMemory()
        let acme = try editor(db).add(name: "acme")
        #expect(try editor(db).rename(id: acme.id!, to: " ACME ").name == "ACME")
        #expect(try editor(db).rename(id: acme.id!, to: "Acme Corp").name == "Acme Corp")
        #expect(throws: ClientEditError.blank) { try editor(db).rename(id: acme.id!, to: "   ") }
        #expect(try ClientRepository(database: db).find(id: acme.id!)?.name == "Acme Corp")
    }

    @Test func renamingAMissingClientIsRefused() throws {
        let db = try PunchcardCore.Database.inMemory()
        #expect(throws: ClientEditError.missing) { try editor(db).rename(id: 999, to: "Ghost") }
        #expect(throws: ClientEditError.missing) { try editor(db).archive(id: 999) }
        #expect(throws: ClientEditError.missing) { try editor(db).unarchive(id: 999) }
    }

    @Test func deletingAClientWithEntriesIsRefusedWithTheArchiveHint() throws {
        let db = try PunchcardCore.Database.inMemory()
        let acme = try editor(db).add(name: "Acme")
        try EntryRepository(database: db).insert(entry(acme.id!, start: t0, end: t0 + 60))

        #expect(throws: ClientEditError.hasEntries) { try editor(db).delete(id: acme.id!) }
        #expect(try ClientRepository(database: db).find(id: acme.id!) == acme)
        let message = try #require(ClientEditError.hasEntries.errorDescription)
        #expect(message.contains("Archive it instead"))
    }

    @Test func deletingAnEmptyClientSucceedsAndAMissingOneIsNotAnError() throws {
        let db = try PunchcardCore.Database.inMemory()
        let acme = try editor(db).add(name: "Acme")
        try editor(db).delete(id: acme.id!)
        #expect(try ClientRepository(database: db).find(id: acme.id!) == nil)
        try editor(db).delete(id: acme.id!)
    }

    @Test func archivingTheOnlyActiveClientIsRefused() throws {
        let db = try PunchcardCore.Database.inMemory()
        let only = try #require(try ClientRepository(database: db).all().first)

        #expect(throws: ClientEditError.archivingLastActive) { try editor(db).archive(id: only.id!) }
        #expect(try ClientRepository(database: db).all() == [only])
        #expect(ClientEditError.archivingLastActive.errorDescription == "Add another client before archiving this one.")

        // With a second client either can be archived, and then the other is the only one left.
        let acme = try editor(db).add(name: "Acme")
        try editor(db).archive(id: only.id!)
        #expect(throws: ClientEditError.archivingLastActive) { try editor(db).archive(id: acme.id!) }
        #expect(try ClientRepository(database: db).all().map(\.name) == ["Acme"])
    }

    @Test func deletingTheOnlyActiveClientIsRefused() throws {
        let db = try PunchcardCore.Database.inMemory()
        let only = try #require(try ClientRepository(database: db).all().first)

        #expect(throws: ClientEditError.deletingLastActive) { try editor(db).delete(id: only.id!) }
        #expect(try ClientRepository(database: db).all() == [only])
        #expect(ClientEditError.deletingLastActive.errorDescription == "Add another client before deleting this one.")

        // An archived client can still be deleted while one active client remains.
        let acme = try editor(db).add(name: "Acme")
        try editor(db).archive(id: acme.id!)
        try editor(db).delete(id: acme.id!)
        #expect(try ClientRepository(database: db).find(id: acme.id!) == nil)
        #expect(throws: ClientEditError.deletingLastActive) { try editor(db).delete(id: only.id!) }
    }

    @Test func archivingTheRunningClientIsRefusedWhileItRuns() throws {
        let db = try PunchcardCore.Database.inMemory()
        let acme = try editor(db).add(name: "Acme")
        let globex = try editor(db).add(name: "Globex")
        let engine = TimerEngine(database: db, now: { t0 + 200 })
        try engine.start(clientID: acme.id!)

        #expect(throws: ClientEditError.running) { try editor(db).archive(id: acme.id!) }
        #expect(try ClientRepository(database: db).find(id: acme.id!)?.archivedAt == nil)
        #expect(ClientEditError.running.errorDescription == "This client's clock is running. Stop it before archiving.")

        // Another client can be archived while Acme runs.
        #expect(try editor(db).archive(id: globex.id!).archivedAt == t0 + 100)

        // Once stopped, Acme can be archived too, and its entry stays.
        try engine.stop()
        let archived = try editor(db, now: t0 + 300.9).archive(id: acme.id!)
        #expect(archived.archivedAt == t0 + 300)
        #expect(try ClientRepository(database: db).find(id: acme.id!) == archived)
        #expect(try EntryRepository(database: db).entries(overlapping: t0, t0 + 1000).map(\.clientID) == [acme.id!])
    }

    @Test func archiveAndUnarchiveRoundTripAndRepeatsChangeNothing() throws {
        let db = try PunchcardCore.Database.inMemory()
        let acme = try editor(db).add(name: "Acme")
        let archived = try editor(db).archive(id: acme.id!)
        #expect(archived.archivedAt == t0 + 100)
        #expect(try editor(db, now: t0 + 500).archive(id: acme.id!) == archived)
        #expect(try ClientRepository(database: db).all().map(\.name) == ["Default"])

        let active = try editor(db).unarchive(id: acme.id!)
        #expect(active.archivedAt == nil)
        #expect(try editor(db).unarchive(id: acme.id!) == active)
        #expect(try ClientRepository(database: db).all().map(\.name) == ["Acme", "Default"])
    }

    @Test func archivedClientsLeaveTheDropdownAndSingleClientModeReturns() throws {
        let db = try PunchcardCore.Database.inMemory()
        #expect(try TrackerSnapshot.load(from: db, now: t0).isSingleClient)

        let acme = try editor(db).add(name: "Acme")
        try EntryRepository(database: db).insert(entry(acme.id!, start: t0 - 3600, end: t0 - 1800))
        let two = try TrackerSnapshot.load(from: db, now: t0)
        #expect(!two.isSingleClient)
        #expect(two.clients.map(\.name) == ["Acme", "Default"])

        try editor(db).archive(id: acme.id!)
        let one = try TrackerSnapshot.load(from: db, now: t0)
        #expect(one.isSingleClient)
        #expect(one.clients.map(\.name) == ["Default"])
        // The archived client's time still counts in history and totals.
        #expect(one.name(of: acme.id!) == "Acme")
        #expect(one.today.seconds(for: acme.id!) == 1800)
        #expect(one.today.overall == 1800)
    }
}

@Suite struct ClientsViewModelTests {
    @Test func listsActiveClientsByNameThenArchivedOnesWithCountsAndFlags() throws {
        let db = try PunchcardCore.Database.inMemory()
        let acme = try editor(db).add(name: "acme")
        let globex = try editor(db).add(name: "Globex")
        let zeta = try editor(db).add(name: "Zeta")
        let entries = EntryRepository(database: db)
        try entries.insert(entry(acme.id!, start: t0, end: t0 + 60))
        try entries.insert(entry(acme.id!, start: t0 + 100, end: t0 + 160))
        try entries.insert(entry(zeta.id!, start: t0 + 200, end: nil))
        try editor(db).archive(id: globex.id!)

        let vm = try ClientsViewModel.load(from: db)
        #expect(vm.rows.map(\.name) == ["acme", "Default", "Zeta", "Globex"])
        #expect(vm.rows.map(\.entryCount) == [2, 0, 1, 0])
        #expect(vm.rows.map(\.isArchived) == [false, false, false, true])
        #expect(vm.rows.map(\.isRunning) == [false, false, true, false])
        #expect(vm.rows.map(\.canDelete) == [false, true, false, true])
        #expect(vm.rows.map(\.canArchive) == [true, true, false, false])
        #expect(vm.rows.map(\.suggestsArchive) == [true, false, true, false])
        #expect(vm.rows.map(\.isOnlyActive) == [false, false, false, false])
        #expect(vm.activeCount == 3)
        #expect(vm.row(id: globex.id!)?.client.archivedAt == t0 + 100)
        #expect(vm.row(id: 999) == nil)
    }

    @Test func buildsRowsFromValuesWithoutADatabase() {
        let clients = [
            Client(id: 1, name: "Acme", createdAt: t0),
            Client(id: 2, name: "Globex", archivedAt: t0, createdAt: t0),
            Client(id: 3, name: "Initech", createdAt: t0),
            Client(name: "unsaved", createdAt: t0),
        ]
        let vm = ClientsViewModel(clients: clients, entryCounts: [2: 4], runningClientID: 1)
        #expect(vm.rows.map(\.id) == [1, 3, 2])
        #expect(vm.rows[0].isRunning && !vm.rows[0].canArchive && vm.rows[0].canDelete)
        #expect(vm.rows[2].entryCount == 4 && !vm.rows[2].canDelete && !vm.rows[2].suggestsArchive)
        #expect(vm.activeCount == 2)
    }

    @Test func theOnlyActiveClientCanBeNeitherArchivedNorDeleted() {
        let clients = [
            Client(id: 1, name: "Acme", createdAt: t0),
            Client(id: 2, name: "Globex", archivedAt: t0, createdAt: t0),
            Client(id: 3, name: "Initech", archivedAt: t0, createdAt: t0),
        ]
        let vm = ClientsViewModel(clients: clients, entryCounts: [1: 2, 3: 1], runningClientID: nil)
        #expect(vm.rows.map(\.isOnlyActive) == [true, false, false])
        #expect(vm.rows.map(\.canArchive) == [false, false, false])
        #expect(vm.rows.map(\.canDelete) == [false, true, false])
        #expect(vm.rows.map(\.suggestsArchive) == [false, false, false])
    }
}
