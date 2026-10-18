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
private let names: [Int64: String] = [1: "Acme", 2: "Globex", 3: "Initech"]

private func entry(_ id: Int64, _ clientID: Int64, _ start: Date, _ end: Date?, note: String = "") -> Entry {
    Entry(id: id, clientID: clientID, startedAt: start, endedAt: end, note: note, createdAt: start, updatedAt: start)
}

private func day(_ date: Date) -> DateInterval {
    Period.day.interval(containing: date, calendar: chicago, weekStartDay: 1)
}

private func week(_ date: Date, weekStartDay: Int = 1) -> DateInterval {
    Period.week.interval(containing: date, calendar: chicago, weekStartDay: weekStartDay)
}

// Tuesday 23:00 to Wednesday 01:00, crossing midnight.
private let acrossMidnight = entry(10, 2, local(2026, 10, 13, 23), local(2026, 10, 14, 1))
private let wednesdayMorning = entry(11, 1, local(2026, 10, 14, 9), local(2026, 10, 14, 11, 30), note: "Design review")
private let runningSince10 = entry(12, 1, local(2026, 10, 14, 15, 20), nil)

@Suite struct DayViewModelTests {
    @Test func listsTheDaysEntriesInStartOrderWithTheirPartOfTheDay() {
        let vm = DayViewModel(
            entries: [runningSince10, wednesdayMorning, acrossMidnight], clientNames: names,
            interval: day(now), now: now)

        #expect(vm.rows.map(\.id) == [10, 11, 12])
        #expect(vm.rows.map(\.clientName) == ["Globex", "Acme", "Acme"])
        #expect(vm.rows.map(\.secondsInDay) == [3600, 9000, 600])
        #expect(vm.rows.map(\.seconds) == [7200, 9000, 600])
        #expect(vm.rows.map(\.startsBeforeDay) == [true, false, false])
        #expect(vm.rows.map(\.endsAfterDay) == [false, false, false])
        #expect(vm.rows.map(\.isPartial) == [true, false, false])
        #expect(vm.rows.map(\.isRunning) == [false, false, true])
        #expect(vm.rows[1].entry.note == "Design review")
        #expect(vm.totalSeconds == 3600 + 9000 + 600)
    }

    @Test func midnightCrossingEntryAppearsOnBothDays() {
        let tuesday = DayViewModel(
            entries: [acrossMidnight, wednesdayMorning], clientNames: names,
            interval: day(local(2026, 10, 13, 12)), now: now)
        #expect(tuesday.rows.map(\.id) == [10])
        #expect(tuesday.rows[0].secondsInDay == 3600)
        #expect(tuesday.rows[0].seconds == 7200)
        #expect(tuesday.rows[0].endsAfterDay)
        #expect(!tuesday.rows[0].startsBeforeDay)
        #expect(tuesday.totalSeconds == 3600)

        let monday = DayViewModel(
            entries: [acrossMidnight], clientNames: names, interval: day(local(2026, 10, 12, 12)), now: now)
        #expect(monday.rows.isEmpty)
        #expect(monday.totalSeconds == 0)
    }

    @Test func entryEndingAtMidnightBelongsToTheDayBeforeOnly() {
        let untilMidnight = entry(20, 1, local(2026, 10, 13, 22), local(2026, 10, 14, 0))
        let fromMidnight = entry(21, 1, local(2026, 10, 14, 0), local(2026, 10, 14, 0, 30))
        let tuesday = DayViewModel(
            entries: [untilMidnight, fromMidnight], clientNames: names, interval: day(local(2026, 10, 13, 12)), now: now)
        let wednesday = DayViewModel(
            entries: [untilMidnight, fromMidnight], clientNames: names, interval: day(now), now: now)
        #expect(tuesday.rows.map(\.id) == [20])
        #expect(wednesday.rows.map(\.id) == [21])
        #expect(tuesday.rows[0].isPartial == false)
    }

    @Test func runningEntryPastMidnightIsPartialOnItsFirstDay() {
        let overnight = entry(30, 1, local(2026, 10, 13, 22), nil)
        let tuesday = DayViewModel(entries: [overnight], clientNames: names, interval: day(local(2026, 10, 13, 12)), now: now)
        #expect(tuesday.rows[0].secondsInDay == 7200)
        #expect(tuesday.rows[0].endsAfterDay)
        #expect(tuesday.rows[0].isRunning)
        let wednesday = DayViewModel(entries: [overnight], clientNames: names, interval: day(now), now: now)
        #expect(wednesday.rows[0].secondsInDay == 15 * 3600 + 30 * 60)
        #expect(wednesday.rows[0].startsBeforeDay)
    }

    @Test func flagsOverlappingRowsAndNamesUnknownClientsByID() {
        let a = entry(40, 1, local(2026, 10, 14, 9), local(2026, 10, 14, 10))
        let b = entry(41, 9, local(2026, 10, 14, 9, 30), local(2026, 10, 14, 11))
        let c = entry(42, 1, local(2026, 10, 14, 11), local(2026, 10, 14, 12))
        let vm = DayViewModel(entries: [a, b, c], clientNames: names, interval: day(now), now: now)
        #expect(vm.rows.map(\.overlaps) == [true, true, false])
        #expect(vm.rows[1].clientName == "Client 9")
    }

    @Test func loadReadsTheDayAndFlagsOverlapsWithEntriesOnOtherDays() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clients = ClientRepository(database: db)
        let defaultID = try #require(try clients.all().first?.id)
        let acmeID = try #require(try clients.insert(name: "Acme").id)
        let entries = EntryRepository(database: db)
        // Monday 22:00 to Tuesday 02:00: on Tuesday's list, and it overlaps the next one.
        let overnight = try entries.insert(entry(nil, acmeID, local(2026, 10, 12, 22), local(2026, 10, 13, 2)))
        // Monday 22:30 to 23:00: not on Tuesday's list, but it makes `overnight` overlap.
        try entries.insert(entry(nil, defaultID, local(2026, 10, 12, 22, 30), local(2026, 10, 12, 23)))
        let tuesday = try entries.insert(entry(nil, defaultID, local(2026, 10, 13, 9), local(2026, 10, 13, 10), note: "x"))

        let vm = try DayViewModel.load(from: db, containing: local(2026, 10, 13, 12), now: now, calendar: chicago)

        #expect(vm.interval == day(local(2026, 10, 13, 12)))
        #expect(vm.rows.map(\.id) == [overnight.id, tuesday.id])
        #expect(vm.rows.map(\.clientName) == ["Acme", "Default"])
        #expect(vm.rows.map(\.overlaps) == [true, false])
        #expect(vm.rows.map(\.secondsInDay) == [7200, 3600])
        #expect(vm.rows[1].entry == tuesday)
        #expect(vm.totalSeconds == 10800)
    }

    private func entry(_ id: Int64?, _ clientID: Int64, _ start: Date, _ end: Date?, note: String = "") -> Entry {
        Entry(id: id, clientID: clientID, startedAt: start, endedAt: end, note: note, createdAt: start, updatedAt: start)
    }
}

@Suite struct WeekViewModelTests {
    @Test func buildsSevenDayColumnsAndSplitsAMidnightCrossingEntry() {
        let thursday = entry(13, 2, local(2026, 10, 15, 8), local(2026, 10, 15, 12))
        let vm = WeekViewModel(
            entries: [acrossMidnight, wednesdayMorning, runningSince10, thursday], clientNames: names,
            interval: week(now), now: now, calendar: chicago)

        #expect(vm.days.count == 7)
        #expect(vm.days.map(\.interval.start) == (12...18).map { local(2026, 10, $0, 0) })
        #expect(vm.days.last?.interval.end == local(2026, 10, 19, 0))
        #expect(vm.days.map(\.seconds) == [0, 3600, 3600 + 9000 + 600, 4 * 3600, 0, 0, 0])
        #expect(vm.rows.map(\.name) == ["Acme", "Globex"])
        #expect(vm.rows[0].seconds == [0, 0, 9600, 0, 0, 0, 0])
        #expect(vm.rows[1].seconds == [0, 3600, 3600, 4 * 3600, 0, 0, 0])
        #expect(vm.rows.map(\.total) == [9600, 6 * 3600])
        #expect(vm.totalSeconds == 9600 + 6 * 3600)
    }

    @Test func emptyWeekHasColumnsButNoRows() {
        let vm = WeekViewModel(entries: [], clientNames: names, interval: week(now), now: now, calendar: chicago)
        #expect(vm.days.map(\.seconds) == [0, 0, 0, 0, 0, 0, 0])
        #expect(vm.rows.isEmpty)
        #expect(vm.totalSeconds == 0)
    }

    @Test func entryAcrossTheWeekBoundaryOnlyCountsItsOwnPart() {
        // Sunday October 11 23:00 to Monday October 12 01:00.
        let acrossWeeks = entry(14, 1, local(2026, 10, 11, 23), local(2026, 10, 12, 1))
        let monday = WeekViewModel(entries: [acrossWeeks], clientNames: names, interval: week(now), now: now, calendar: chicago)
        #expect(monday.days.map(\.seconds) == [3600, 0, 0, 0, 0, 0, 0])
        #expect(monday.rows == [.init(id: 1, name: "Acme", seconds: [3600, 0, 0, 0, 0, 0, 0])])

        let sunday = WeekViewModel(
            entries: [acrossWeeks], clientNames: names, interval: week(now, weekStartDay: 7), now: now, calendar: chicago)
        #expect(sunday.days.first?.interval.start == local(2026, 10, 11, 0))
        #expect(sunday.days.map(\.seconds) == [3600, 3600, 0, 0, 0, 0, 0])
        #expect(sunday.totalSeconds == 7200)
    }

    @Test func loadUsesTheWeekStartSetting() throws {
        let db = try PunchcardCore.Database.inMemory()
        let defaultID = try #require(try ClientRepository(database: db).all().first?.id)
        try EntryRepository(database: db).insert(entry(nil, defaultID, local(2026, 10, 11, 23), local(2026, 10, 12, 1)))

        let monday = try WeekViewModel.load(from: db, containing: now, now: now, calendar: chicago)
        #expect(monday.interval == week(now))
        #expect(monday.totalSeconds == 3600)
        #expect(monday.rows.map(\.name) == ["Default"])

        try SettingsStore(database: db).setWeekStartDay(7)
        let sunday = try WeekViewModel.load(from: db, containing: now, now: now, calendar: chicago)
        #expect(sunday.interval == week(now, weekStartDay: 7))
        #expect(sunday.totalSeconds == 7200)
    }

    private func entry(_ id: Int64?, _ clientID: Int64, _ start: Date, _ end: Date?) -> Entry {
        Entry(id: id, clientID: clientID, startedAt: start, endedAt: end, createdAt: start, updatedAt: start)
    }
}

@Suite struct EntryOverlapsTests {
    @Test func flagsPairsThatShareAnInstantButNotAdjacentOnes() {
        let a = entry(1, 1, local(2026, 10, 14, 9), local(2026, 10, 14, 10))
        let b = entry(2, 2, local(2026, 10, 14, 9, 30), local(2026, 10, 14, 11))
        let c = entry(3, 1, local(2026, 10, 14, 11), local(2026, 10, 14, 12))  // touches b only
        let running = entry(4, 2, local(2026, 10, 14, 11, 30), nil)  // overlaps c up to now
        let alone = entry(5, 1, local(2026, 10, 14, 13), local(2026, 10, 14, 14))
        let entries = [alone, running, c, b, a]

        #expect(EntryOverlaps.pairs(in: entries, now: local(2026, 10, 14, 12)) == [.init(1, 2), .init(3, 4)])
        #expect(EntryOverlaps.ids(in: entries, now: local(2026, 10, 14, 12)) == [1, 2, 3, 4])
    }

    @Test func oneEntryCanOverlapSeveralAndZeroLengthEntriesNeverOverlap() {
        let long = entry(1, 1, local(2026, 10, 14, 8), local(2026, 10, 14, 18))
        let first = entry(2, 1, local(2026, 10, 14, 9), local(2026, 10, 14, 10))
        let second = entry(3, 1, local(2026, 10, 14, 15), local(2026, 10, 14, 16))
        let instant = entry(4, 1, local(2026, 10, 14, 12), local(2026, 10, 14, 12))
        let pairs = EntryOverlaps.pairs(in: [long, first, second, instant], now: now)
        #expect(pairs == [.init(1, 2), .init(1, 3)])
    }

    @Test func runningEntryOverlapsNothingBeforeItStarted() {
        let earlier = entry(1, 1, local(2026, 10, 14, 9), local(2026, 10, 14, 10))
        let running = entry(2, 1, local(2026, 10, 14, 10), nil)
        #expect(EntryOverlaps.pairs(in: [earlier, running], now: now).isEmpty)
        #expect(!EntryOverlaps.overlap(earlier, running, now: now))
    }

    @Test func draftOverlapUsesTheDraftTimes() {
        let other = entry(1, 1, local(2026, 10, 14, 9), local(2026, 10, 14, 10))
        var draft = EntryDraft(clientID: 2, startedAt: local(2026, 10, 14, 10), endedAt: local(2026, 10, 14, 11))
        #expect(!draft.overlaps(other, now: now))
        draft.startedAt = local(2026, 10, 14, 9, 59)
        #expect(draft.overlaps(other, now: now))
        let runningDraft = EntryDraft(clientID: 2, startedAt: local(2026, 10, 14, 8), endedAt: nil)
        #expect(runningDraft.overlaps(other, now: now))
    }
}

@Suite struct EntryEditorTests {
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date
        init(_ date: Date) { self.date = date }
        var now: Date { lock.withLock { date } }
        func advance(by seconds: TimeInterval) { lock.withLock { date += seconds } }
    }

    @Test func endBeforeStartIsRejectedWithAMessage() throws {
        let draft = EntryDraft(clientID: 1, startedAt: local(2026, 10, 14, 10), endedAt: local(2026, 10, 14, 9))
        #expect(throws: EntryEditError.endBeforeStart) { try draft.validate() }
        #expect(EntryEditError.endBeforeStart.localizedDescription == "End can't be before start.")
        #expect(EntryEditError.noClient.localizedDescription == "Choose a client.")

        let db = try PunchcardCore.Database.inMemory()
        let defaultID = try #require(try ClientRepository(database: db).all().first?.id)
        let editor = EntryEditor(database: db, now: { now })
        #expect(throws: EntryEditError.endBeforeStart) {
            try editor.save(EntryDraft(clientID: defaultID, startedAt: local(2026, 10, 14, 10), endedAt: local(2026, 10, 14, 9)))
        }
        #expect(throws: EntryEditError.noClient) {
            try editor.save(EntryDraft(clientID: nil, startedAt: local(2026, 10, 14, 9), endedAt: local(2026, 10, 14, 10)))
        }
        #expect(try EntryRepository(database: db).entries(overlapping: .distantPast, .distantFuture).isEmpty)
    }

    @Test func endEqualToStartIsAllowed() throws {
        let draft = EntryDraft(clientID: 1, startedAt: local(2026, 10, 14, 10), endedAt: local(2026, 10, 14, 10))
        try draft.validate()
        try EntryDraft(clientID: 1, startedAt: local(2026, 10, 14, 10), endedAt: nil).validate()
    }

    @Test func savesAManualEntryForAPastDay() throws {
        let db = try PunchcardCore.Database.inMemory()
        let defaultID = try #require(try ClientRepository(database: db).all().first?.id)
        let editor = EntryEditor(database: db, now: { now })

        let draft = EntryDraft(
            clientID: defaultID, startedAt: local(2026, 10, 9, 13, 0, 0) + 0.7, endedAt: local(2026, 10, 9, 15, 30),
            note: "  Site visit \n")
        let saved = try editor.save(draft)

        #expect(saved.id != nil)
        #expect(saved.clientID == defaultID)
        #expect(saved.startedAt == local(2026, 10, 9, 13))
        #expect(saved.endedAt == local(2026, 10, 9, 15, 30))
        #expect(saved.note == "Site visit")
        #expect(saved.createdAt == now)
        #expect(saved.updatedAt == now)
        #expect(try EntryRepository(database: db).find(id: #require(saved.id)) == saved)
        let friday = try DayViewModel.load(from: db, containing: local(2026, 10, 9, 12), now: now, calendar: chicago)
        #expect(friday.rows.map(\.id) == [saved.id])
        #expect(friday.totalSeconds == 9000)
    }

    @Test func manualDraftDefaultsToNineToTenOnTheDay() {
        let draft = EntryDraft.manual(clientID: 1, on: local(2026, 10, 9, 17, 45), calendar: chicago)
        #expect(draft.startedAt == local(2026, 10, 9, 9))
        #expect(draft.endedAt == local(2026, 10, 9, 10))
        #expect(draft.note == "")
        #expect(!draft.isRunning)
    }

    @Test func updateChangesTheFieldsAndUpdatedAtButKeepsCreatedAt() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clients = ClientRepository(database: db)
        let defaultID = try #require(try clients.all().first?.id)
        let acmeID = try #require(try clients.insert(name: "Acme").id)
        let clock = TestClock(local(2026, 10, 13, 12))
        let engine = TimerEngine(database: db, now: { clock.now })
        let original = try engine.start(clientID: defaultID)
        clock.advance(by: 3600)
        try engine.stop()
        clock.advance(by: 86400)
        let editor = EntryEditor(database: db, now: { clock.now })

        let originalID = try #require(original.id)
        var draft = EntryDraft(try #require(try EntryRepository(database: db).find(id: originalID)))
        #expect(draft == EntryDraft(clientID: defaultID, startedAt: local(2026, 10, 13, 12), endedAt: local(2026, 10, 13, 13)))
        draft.clientID = acmeID
        draft.startedAt = local(2026, 10, 13, 11, 30)
        draft.note = "Moved earlier"
        let updated = try editor.save(draft, replacing: original.id)

        #expect(updated.id == original.id)
        #expect(updated.clientID == acmeID)
        #expect(updated.startedAt == local(2026, 10, 13, 11, 30))
        #expect(updated.endedAt == local(2026, 10, 13, 13))
        #expect(updated.note == "Moved earlier")
        #expect(updated.createdAt == local(2026, 10, 13, 12))
        #expect(updated.updatedAt == local(2026, 10, 14, 13))
        #expect(try EntryRepository(database: db).find(id: #require(original.id)) == updated)
    }

    @Test func rejectedEditLeavesTheStoredEntryUnchanged() throws {
        let db = try PunchcardCore.Database.inMemory()
        let defaultID = try #require(try ClientRepository(database: db).all().first?.id)
        let editor = EntryEditor(database: db, now: { now })
        let saved = try editor.save(EntryDraft(clientID: defaultID, startedAt: local(2026, 10, 13, 9), endedAt: local(2026, 10, 13, 10)))

        var draft = EntryDraft(saved)
        draft.endedAt = local(2026, 10, 13, 8)
        #expect(throws: EntryEditError.endBeforeStart) { try editor.save(draft, replacing: saved.id) }
        #expect(try EntryRepository(database: db).find(id: #require(saved.id)) == saved)
    }

    @Test func editingAStoppedEntryIntoRunningFailsWhileAnotherRuns() throws {
        let db = try PunchcardCore.Database.inMemory()
        let defaultID = try #require(try ClientRepository(database: db).all().first?.id)
        let editor = EntryEditor(database: db, now: { now })
        let stopped = try editor.save(EntryDraft(clientID: defaultID, startedAt: local(2026, 10, 13, 9), endedAt: local(2026, 10, 13, 10)))
        try TimerEngine(database: db).start(clientID: defaultID, at: local(2026, 10, 14, 15))

        var draft = EntryDraft(stopped)
        draft.endedAt = nil
        #expect(throws: EntryEditError.anotherEntryRunning) { try editor.save(draft, replacing: stopped.id) }
        #expect(EntryEditError.anotherEntryRunning.localizedDescription == "Another entry is already running.")
    }

    @Test func editingTheRunningEntryKeepsItRunning() throws {
        let db = try PunchcardCore.Database.inMemory()
        let defaultID = try #require(try ClientRepository(database: db).all().first?.id)
        let running = try TimerEngine(database: db).start(clientID: defaultID, at: local(2026, 10, 14, 15))
        let editor = EntryEditor(database: db, now: { now })

        var draft = EntryDraft(running)
        draft.startedAt = local(2026, 10, 14, 14, 45)
        draft.note = "Call"
        let updated = try editor.save(draft, replacing: running.id)
        #expect(updated.isRunning)
        #expect(try TimerEngine(database: db).running() == updated)

        draft.endedAt = local(2026, 10, 14, 15, 15)
        try editor.save(draft, replacing: running.id)
        #expect(try TimerEngine(database: db).running() == nil)
    }

    @Test func saveOfADeletedEntryThrowsMissingAndDeleteIsIdempotent() throws {
        let db = try PunchcardCore.Database.inMemory()
        let defaultID = try #require(try ClientRepository(database: db).all().first?.id)
        let editor = EntryEditor(database: db, now: { now })
        let saved = try editor.save(EntryDraft(clientID: defaultID, startedAt: local(2026, 10, 13, 9), endedAt: local(2026, 10, 13, 10)))
        let id = try #require(saved.id)

        try editor.delete(id: id)
        #expect(try EntryRepository(database: db).find(id: id) == nil)
        try editor.delete(id: id)
        #expect(throws: EntryEditError.missing) { try editor.save(EntryDraft(saved), replacing: id) }
    }
}
