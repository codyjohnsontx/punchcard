import Foundation
@testable import PunchcardCore
import Testing

private let chicago: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
}()

/// A local America/Chicago wall-clock time.
private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private let now = local(2026, 10, 14, 15, 30)  // a Wednesday
private let acme = Client(id: 1, name: "Acme", createdAt: now)
private let globex = Client(id: 2, name: "Globex", createdAt: now)
private let initech = Client(id: 3, name: "Initech", archivedAt: now, createdAt: now)

private func entry(_ clientID: Int64, _ start: Date, _ end: Date?) -> Entry {
    Entry(clientID: clientID, startedAt: start, endedAt: end, createdAt: start, updatedAt: start)
}

/// A snapshot built directly, without a database.
private func snapshot(
    clients: [Client] = [acme], archived: [Client] = [], entries: [Entry] = [], running: Entry? = nil,
    style: SettingsStore.MenuBarStyle = .time, now: Date = now
) -> TrackerSnapshot {
    let all = entries + (running.map { [$0] } ?? [])
    func totals(_ period: Period) -> Totals {
        Totals(entries: all, in: period.interval(containing: now, calendar: chicago, weekStartDay: 1), now: now)
    }
    return TrackerSnapshot(
        clients: clients,
        clientNames: Dictionary(uniqueKeysWithValues: (clients + archived).map { ($0.id!, $0.name) }),
        running: running, now: now, menuBarStyle: style,
        today: totals(.day), thisWeek: totals(.week), thisMonth: totals(.month))
}

/// Started 1 hour 42 minutes 7 seconds before `now`.
private func running(_ clientID: Int64 = 1) -> Entry {
    entry(clientID, now - (1 * 3600 + 42 * 60 + 7), nil)
}

@Suite struct MenuBarLabelTests {
    @Test func timeStyleRunningWithOneClientShowsTheTimeOnly() {
        #expect(MenuBarLabel(snapshot(running: running())) == .text("● 1:42"))
    }

    @Test func timeStyleRunningWithManyClientsAddsTheClientName() {
        #expect(MenuBarLabel(snapshot(clients: [acme, globex], running: running(2))) == .text("● 1:42 Globex"))
    }

    @Test func timeStyleStoppedWithOneClientShowsTheIcon() {
        #expect(MenuBarLabel(snapshot()) == .icon(systemName: "clock"))
    }

    @Test func timeStyleStoppedWithManyClientsShowsTheIcon() {
        #expect(MenuBarLabel(snapshot(clients: [acme, globex])) == .icon(systemName: "clock"))
    }

    @Test func iconStyleShowsClockOrFilledClock() {
        #expect(MenuBarLabel(snapshot(style: .icon)) == .icon(systemName: "clock"))
        #expect(MenuBarLabel(snapshot(running: running(), style: .icon)) == .icon(systemName: "clock.fill"))
        #expect(MenuBarLabel(snapshot(clients: [acme, globex], running: running(2), style: .icon)) == .icon(systemName: "clock.fill"))
    }

    @Test func freshClockTicksFromZeroToOneMinute() {
        let started = entry(1, now, nil)
        #expect(MenuBarLabel(snapshot(running: started, now: now)) == .text("● 0:00"))
        #expect(MenuBarLabel(snapshot(running: started, now: now + 59)) == .text("● 0:00"))
        #expect(MenuBarLabel(snapshot(running: started, now: now + 60)) == .text("● 0:01"))
    }

    @Test func clientNameComesFromAllClientsEvenWhenArchived() {
        // Only one active client, so no name in the menu bar; but the dropdown headline uses it.
        let archivedRunning = snapshot(clients: [acme], archived: [initech], running: running(3))
        #expect(MenuBarLabel(archivedRunning) == .text("● 1:42"))
        #expect(archivedRunning.runningClientName == "Initech")
    }

    @Test func clockMovedBackPastTheStartReadsZero() {
        let started = entry(1, now + 600, nil)
        #expect(snapshot(running: started).runningSeconds == 0)
        #expect(MenuBarLabel(snapshot(running: started)) == .text("● 0:00"))
    }
}

@Suite struct DropdownViewModelTests {
    @Test func singleClientStoppedHasOneStartButtonAndOverallTotals() {
        let yesterday = entry(1, local(2026, 10, 13, 9), local(2026, 10, 13, 11, 30))
        let today = entry(1, local(2026, 10, 14, 9), local(2026, 10, 14, 10, 15))
        let vm = DropdownViewModel(snapshot(entries: [yesterday, today]))

        #expect(vm.isSingleClient)
        #expect(!vm.isRunning)
        #expect(vm.headline == nil)
        #expect(vm.singleClientID == 1)
        #expect(vm.clientRows.isEmpty)
        #expect(vm.totalsRows == [
            .init(id: "all", name: "All", today: "1:15", week: "3:45", month: "3:45"),
        ])
    }

    @Test func singleClientRunningShowsTheClockWithoutAName() {
        let vm = DropdownViewModel(snapshot(running: running()))
        #expect(vm.isRunning)
        #expect(vm.headline == "● 1:42:07")
        #expect(vm.totalsRows.map(\.today) == ["1:42"])
    }

    @Test func multiClientRunningShowsRowsPerClientAndAnAllRow() {
        let globexEarlier = entry(2, local(2026, 10, 14, 8), local(2026, 10, 14, 9))
        let lastWeek = entry(2, local(2026, 10, 9, 8), local(2026, 10, 9, 12))
        let vm = DropdownViewModel(snapshot(clients: [acme, globex], entries: [globexEarlier, lastWeek], running: running(1)))

        #expect(!vm.isSingleClient)
        #expect(vm.headline == "● 1:42:07 Acme")
        #expect(vm.clientRows == [
            .init(id: 1, name: "Acme", isRunning: true, clock: "1:42:07"),
            .init(id: 2, name: "Globex", isRunning: false, clock: nil),
        ])
        #expect(vm.totalsRows == [
            .init(id: "client-1", name: "Acme", today: "1:42", week: "1:42", month: "1:42"),
            .init(id: "client-2", name: "Globex", today: "1:00", week: "1:00", month: "5:00"),
            .init(id: "all", name: "All", today: "2:42", week: "2:42", month: "6:42"),
        ])
    }

    @Test func multiClientStoppedHasNoHeadlineAndStartOnEveryRow() {
        let vm = DropdownViewModel(snapshot(clients: [acme, globex]))
        #expect(vm.headline == nil)
        #expect(vm.clientRows.map(\.isRunning) == [false, false])
        #expect(vm.clientRows.map(\.clock) == [nil, nil])
        #expect(vm.totalsRows.map(\.name) == ["Acme", "Globex", "All"])
        #expect(vm.totalsRows.map(\.month) == ["0:00", "0:00", "0:00"])
    }

    @Test func archivedClientWithTimeAppearsInTotalsButNotInClientRows() {
        let archivedToday = entry(3, local(2026, 10, 14, 7), local(2026, 10, 14, 8))
        let vm = DropdownViewModel(snapshot(clients: [acme, globex], archived: [initech], entries: [archivedToday]))

        #expect(vm.clientRows.map(\.name) == ["Acme", "Globex"])
        #expect(vm.totalsRows.map(\.name) == ["Acme", "Globex", "Initech", "All"])
        #expect(vm.totalsRows.map(\.today) == ["0:00", "0:00", "1:00", "1:00"])
    }

    @Test func runningArchivedClientGetsARowSoItCanBeStopped() {
        let vm = DropdownViewModel(snapshot(clients: [acme, globex], archived: [initech], running: running(3)))
        #expect(vm.headline == "● 1:42:07 Initech")
        #expect(vm.clientRows.map(\.name) == ["Acme", "Globex", "Initech"])
        #expect(vm.clientRows.last?.isRunning == true)
    }

    @Test func noActiveClientsLeavesNothingToStart() {
        let vm = DropdownViewModel(snapshot(clients: []))
        #expect(vm.isSingleClient)
        #expect(vm.singleClientID == nil)
        #expect(vm.clientRows.isEmpty)
    }
}

@Suite struct TrackerSnapshotTests {
    @Test func loadsClientsRunningEntrySettingsAndTotals() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clients = ClientRepository(database: db)
        let defaultID = try #require(try clients.all().first?.id)
        let acmeID = try #require(try clients.insert(name: "Acme").id)
        var archived = try clients.insert(name: "Old")
        archived.archivedAt = now
        try clients.update(archived)
        let entries = EntryRepository(database: db)
        try entries.insert(entry(acmeID, local(2026, 10, 14, 9), local(2026, 10, 14, 10)))
        try entries.insert(entry(archived.id!, local(2026, 10, 13, 9), local(2026, 10, 13, 10)))
        try entries.insert(entry(defaultID, local(2026, 9, 30, 23), local(2026, 10, 1, 1)))
        try SettingsStore(database: db).setMenuBarStyle(.icon)
        let running = try TimerEngine(database: db).start(clientID: defaultID, at: now - 600)

        let snapshot = try TrackerSnapshot.load(from: db, now: now, calendar: chicago)

        #expect(snapshot.clients.map(\.name) == ["Acme", "Default"])
        #expect(snapshot.clientNames == [defaultID: "Default", acmeID: "Acme", archived.id!: "Old"])
        #expect(snapshot.running == running)
        #expect(snapshot.now == now)
        #expect(snapshot.menuBarStyle == .icon)
        #expect(!snapshot.isSingleClient)
        #expect(snapshot.runningSeconds == 600)
        #expect(snapshot.runningClientName == "Default")
        #expect(snapshot.today.byClient == [acmeID: 3600, defaultID: 600])
        #expect(snapshot.thisWeek.byClient == [acmeID: 3600, archived.id!: 3600, defaultID: 600])
        // The month clips the September 30 23:00 to October 1 01:00 entry to its October hour.
        #expect(snapshot.thisMonth.byClient == [acmeID: 3600, archived.id!: 3600, defaultID: 4200])
        #expect(MenuBarLabel(snapshot) == .icon(systemName: "clock.fill"))
    }

    @Test func weekStartSettingShapesTheWeekTotal() throws {
        let db = try PunchcardCore.Database.inMemory()
        let defaultID = try #require(try ClientRepository(database: db).all().first?.id)
        // Sunday October 11, 2026, 23:00 to Monday 01:00: in this week only with a Sunday start.
        try EntryRepository(database: db).insert(entry(defaultID, local(2026, 10, 11, 23), local(2026, 10, 12, 1)))

        #expect(try TrackerSnapshot.load(from: db, now: now, calendar: chicago).thisWeek.overall == 3600)
        try SettingsStore(database: db).setWeekStartDay(7)
        #expect(try TrackerSnapshot.load(from: db, now: now, calendar: chicago).thisWeek.overall == 7200)
    }

    @Test func freshDatabaseIsSingleClientAndStopped() throws {
        let snapshot = try TrackerSnapshot.load(from: PunchcardCore.Database.inMemory(), now: now, calendar: chicago)
        #expect(snapshot.isSingleClient)
        #expect(snapshot.clients.map(\.name) == ["Default"])
        #expect(snapshot.running == nil)
        #expect(snapshot.menuBarStyle == .time)
        #expect(MenuBarLabel(snapshot) == .icon(systemName: "clock"))
        let vm = DropdownViewModel(snapshot)
        #expect(vm.singleClientID == snapshot.clients[0].id)
        #expect(vm.totalsRows.map(\.today) == ["0:00"])
    }
}
