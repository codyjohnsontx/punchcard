import Foundation
@testable import PunchcardCore
import Testing

private let chicago: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    return calendar
}()

/// A local America/Chicago wall-clock time.
private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    chicago.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func timed(_ clientID: Int64, _ start: Date, _ end: Date?) -> Entry {
    Entry(clientID: clientID, startedAt: start, endedAt: end, createdAt: start, updatedAt: start)
}

private func timed(_ start: Date, _ end: Date?) -> Entry {
    timed(1, start, end)
}

private func total(_ entries: [Entry], _ period: Period, containing date: Date, weekStartDay: Int = 1,
                   now: Date = local(2027, 1, 1, 0)) -> Int {
    let interval = period.interval(containing: date, calendar: chicago, weekStartDay: weekStartDay)
    return Totals(entries: entries, in: interval, now: now).overall
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    var now: Date { lock.withLock { date } }

    func advance(by seconds: TimeInterval) { lock.withLock { date += seconds } }
}

private func secondClient(_ db: PunchcardCore.Database) throws -> Int64 {
    try #require(ClientRepository(database: db).insert(name: "Acme").id)
}

private func defaultClientID(_ db: PunchcardCore.Database) throws -> Int64 {
    try #require(ClientRepository(database: db).all().first { $0.name == "Default" }?.id)
}

@Suite struct TimerEngineTests {
    @Test func startThenStopRecordsOneEntry() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clock = TestClock(local(2026, 10, 12, 9))
        let engine = TimerEngine(database: db, now: { clock.now })
        let client = try defaultClientID(db)

        let started = try engine.start(clientID: client)
        #expect(started.isRunning)
        #expect(started.startedAt == local(2026, 10, 12, 9))
        #expect(try engine.running() == started)

        clock.advance(by: 90 * 60)
        let stopped = try #require(try engine.stop())
        #expect(stopped.id == started.id)
        #expect(stopped.endedAt == local(2026, 10, 12, 10, 30))
        #expect(stopped.updatedAt == stopped.endedAt)
        #expect(try engine.running() == nil)
        #expect(try EntryRepository(database: db).find(id: #require(started.id)) == stopped)
    }

    @Test func startingAnotherClientEndsTheRunningEntryAtTheSameInstant() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let first = try defaultClientID(db)
        let second = try secondClient(db)

        let a = try engine.start(clientID: first, at: local(2026, 10, 12, 9))
        let b = try engine.start(clientID: second, at: local(2026, 10, 12, 11, 15))

        let entries = try EntryRepository(database: db).entries(overlapping: .distantPast, .distantFuture)
        #expect(entries.count == 2)
        #expect(entries[0].id == a.id)
        #expect(entries[0].endedAt == local(2026, 10, 12, 11, 15))
        #expect(entries[1] == b)
        #expect(b.startedAt == entries[0].endedAt)
        #expect(try engine.running() == b)
    }

    @Test func switchEndsAndStartsAtTheSameWholeSecond() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let second = try secondClient(db)
        try engine.start(clientID: defaultClientID(db), at: local(2026, 10, 12, 9))

        let b = try engine.start(clientID: second, at: local(2026, 10, 12, 10) + 0.75)

        let ended = try #require(try EntryRepository(database: db).entries(overlapping: .distantPast, .distantFuture).first)
        #expect(ended.endedAt == local(2026, 10, 12, 10))
        #expect(b.startedAt == local(2026, 10, 12, 10))
    }

    @Test func stopAfterTheClockMovesBackRecordsAZeroLengthEntry() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clock = TestClock(local(2026, 10, 12, 10))
        let engine = TimerEngine(database: db, now: { clock.now })
        let started = try engine.start(clientID: defaultClientID(db))

        clock.advance(by: -55 * 60)
        let stopped = try #require(try engine.stop())

        #expect(stopped.endedAt == started.startedAt)
        #expect(try engine.running() == nil)
    }

    @Test func switchAfterTheClockMovesBackStartsWhereTheEndedEntryEnds() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clock = TestClock(local(2026, 10, 12, 10))
        let engine = TimerEngine(database: db, now: { clock.now })
        let second = try secondClient(db)
        let a = try engine.start(clientID: defaultClientID(db))

        clock.advance(by: -55 * 60)
        let b = try engine.start(clientID: second)

        let ended = try #require(try EntryRepository(database: db).entries(overlapping: .distantPast, .distantFuture).first)
        #expect(ended.endedAt == a.startedAt)
        #expect(b.startedAt == a.startedAt)
        #expect(try engine.running() == b)
    }

    @Test func startingTheRunningClientChangesNothing() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let client = try defaultClientID(db)
        let running = try engine.start(clientID: client, at: local(2026, 10, 12, 9))

        #expect(try engine.start(clientID: client, at: local(2026, 10, 12, 10)) == running)
        #expect(try EntryRepository(database: db).entries(overlapping: .distantPast, .distantFuture) == [running])
    }

    @Test func stopWithNothingRunningIsANoOp() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        #expect(try engine.stop(at: local(2026, 10, 12, 9)) == nil)

        try engine.start(clientID: defaultClientID(db), at: local(2026, 10, 12, 9))
        try engine.stop(at: local(2026, 10, 12, 10))
        #expect(try engine.stop(at: local(2026, 10, 12, 11)) == nil)
        let entries = try EntryRepository(database: db).entries(overlapping: .distantPast, .distantFuture)
        #expect(entries.map(\.endedAt) == [local(2026, 10, 12, 10)])
    }

    @Test func runningEntryTotalCountsUpWithTheInjectedClock() throws {
        let db = try PunchcardCore.Database.inMemory()
        let clock = TestClock(local(2026, 10, 14, 14))
        let engine = TimerEngine(database: db, now: { clock.now })
        let entries = EntryRepository(database: db)
        let client = try defaultClientID(db)
        try engine.start(clientID: client, at: clock.now - 10 * 60)

        func today() throws -> Totals {
            try Totals(for: .day, now: clock.now, calendar: chicago, weekStartDay: 1, entries: entries)
        }
        #expect(try today().overall == 600)
        #expect(try today().seconds(for: client) == 600)
        #expect(DurationFormatter.hoursMinutes(try today().overall) == "0:10")

        clock.advance(by: 5 * 60 + 30)
        #expect(try today().overall == 930)
        #expect(DurationFormatter.hoursMinutes(try today().overall) == "0:15")
    }
}

/// The global shortcut's press: stop if running, else start the most recently used client.
@Suite struct ShortcutPressTests {
    @Test func singleClientPressStartsTheOnlyClientThenStopsIt() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let client = try defaultClientID(db)

        guard case .started(let started) = try engine.press(at: local(2026, 10, 12, 9) + 0.5) else {
            Issue.record("expected the first press to start the clock")
            return
        }
        #expect(started.clientID == client)
        #expect(started.startedAt == local(2026, 10, 12, 9))
        #expect(try engine.running() == started)

        guard case .stopped(let stopped) = try engine.press(at: local(2026, 10, 12, 10)) else {
            Issue.record("expected the second press to stop the clock")
            return
        }
        #expect(stopped.id == started.id)
        #expect(stopped.endedAt == local(2026, 10, 12, 10))
        #expect(try engine.running() == nil)
        #expect(try EntryRepository(database: db).entries(overlapping: .distantPast, .distantFuture) == [stopped])
    }

    @Test func pressWhileRunningStopsWhicheverClientRuns() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let acme = try secondClient(db)
        let running = try engine.start(clientID: acme, at: local(2026, 10, 12, 9))

        let result = try engine.press(at: local(2026, 10, 12, 9, 45))

        var ended = running
        ended.endedAt = local(2026, 10, 12, 9, 45)
        ended.updatedAt = local(2026, 10, 12, 9, 45)
        #expect(result == .stopped(ended))
        #expect(try engine.running() == nil)
    }

    @Test func pressStartsTheClientOfTheLatestStartedEntry() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let defaultClient = try defaultClientID(db)
        let acme = try secondClient(db)
        try engine.start(clientID: defaultClient, at: local(2026, 10, 12, 9))
        try engine.start(clientID: acme, at: local(2026, 10, 12, 10))
        try engine.stop(at: local(2026, 10, 12, 11))

        guard case .started(let started) = try engine.press(at: local(2026, 10, 13, 8)) else {
            Issue.record("expected the press to start the clock")
            return
        }
        #expect(started.clientID == acme)
        #expect(started.startedAt == local(2026, 10, 13, 8))
    }

    @Test func pressSkipsAnArchivedLastUsedClient() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let acme = try secondClient(db)
        let beta = try #require(ClientRepository(database: db).insert(name: "Beta").id)
        try engine.start(clientID: beta, at: local(2026, 10, 12, 8))
        try engine.start(clientID: acme, at: local(2026, 10, 12, 9))
        try engine.stop(at: local(2026, 10, 12, 10))
        try ClientEditor(database: db).archive(id: acme)

        guard case .started(let started) = try engine.press(at: local(2026, 10, 12, 11)) else {
            Issue.record("expected the press to start the clock")
            return
        }
        #expect(started.clientID == beta)
    }

    @Test func pressWithNoEntriesStartsTheFirstActiveClientByName() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let acme = try secondClient(db)

        guard case .started(let started) = try engine.press(at: local(2026, 10, 12, 9)) else {
            Issue.record("expected the press to start the clock")
            return
        }
        #expect(started.clientID == acme)
    }

    @Test func pressWithNoActiveClientChangesNothing() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        try db.queue.write { db in try db.execute(sql: "UPDATE clients SET archived_at = 0") }

        #expect(try engine.press(at: local(2026, 10, 12, 9)) == .noClient)
        #expect(try engine.running() == nil)
        #expect(try EntryRepository(database: db).entries(overlapping: .distantPast, .distantFuture).isEmpty)
    }
}

@Suite struct PeriodTests {
    @Test func dayIsLocalMidnightToMidnight() {
        let interval = Period.day.interval(containing: local(2026, 10, 14, 15, 30), calendar: chicago, weekStartDay: 1)
        #expect(interval == DateInterval(start: local(2026, 10, 14, 0), end: local(2026, 10, 15, 0)))
    }

    @Test(arguments: [
        // ISO week start day, then the start of the week containing Wednesday 2026-10-14.
        (1, 12), (2, 13), (3, 14), (4, 8), (5, 9), (6, 10), (7, 11),
    ])
    func weekStartsOnTheConfiguredDay(weekStartDay: Int, startDay: Int) {
        let interval = Period.week.interval(containing: local(2026, 10, 14, 12), calendar: chicago, weekStartDay: weekStartDay)
        #expect(interval == DateInterval(start: local(2026, 10, startDay, 0), end: local(2026, 10, startDay + 7, 0)))
    }

    @Test func monthIsTheCalendarMonth() {
        let interval = Period.month.interval(containing: local(2026, 10, 14, 12), calendar: chicago, weekStartDay: 1)
        #expect(interval == DateInterval(start: local(2026, 10, 1, 0), end: local(2026, 11, 1, 0)))
    }

    @Test func dstDaysAre23And25HoursLong() {
        let spring = Period.day.interval(containing: local(2026, 3, 8, 12), calendar: chicago, weekStartDay: 1)
        let fall = Period.day.interval(containing: local(2026, 11, 1, 12), calendar: chicago, weekStartDay: 1)
        #expect(spring.duration == 23 * 3600)
        #expect(fall.duration == 25 * 3600)
    }
}

@Suite struct TotalsTests {
    @Test func entryCrossingMidnightSplitsBetweenDays() {
        // 2026-10-12 is a Monday.
        let entries = [timed(local(2026, 10, 12, 23), local(2026, 10, 13, 1))]
        #expect(total(entries, .day, containing: local(2026, 10, 12, 12)) == 3600)
        #expect(total(entries, .day, containing: local(2026, 10, 13, 12)) == 3600)
        #expect(total(entries, .week, containing: local(2026, 10, 12, 12)) == 7200)
    }

    @Test func entryCrossingSundayMidnightSplitsWeeksWhenWeekStartsMonday() {
        let entries = [timed(local(2026, 10, 11, 23), local(2026, 10, 12, 1))]
        #expect(total(entries, .week, containing: local(2026, 10, 11, 12), weekStartDay: 1) == 3600)
        #expect(total(entries, .week, containing: local(2026, 10, 12, 12), weekStartDay: 1) == 3600)
    }

    @Test func entryCrossingSundayMidnightStaysInOneWeekWhenWeekStartsSunday() {
        let entries = [timed(local(2026, 10, 11, 23), local(2026, 10, 12, 1))]
        #expect(total(entries, .week, containing: local(2026, 10, 11, 12), weekStartDay: 7) == 7200)
        #expect(total(entries, .week, containing: local(2026, 10, 12, 12), weekStartDay: 7) == 7200)
    }

    @Test func entryCrossingMonthBoundarySplitsBetweenMonths() {
        let entries = [timed(local(2026, 9, 30, 22), local(2026, 10, 1, 2))]
        #expect(total(entries, .month, containing: local(2026, 9, 15, 12)) == 7200)
        #expect(total(entries, .month, containing: local(2026, 10, 15, 12)) == 7200)
    }

    @Test func entryCrossingMonthBoundaryOnFallBackNightCountsTheRepeatedHour() {
        // 2026-11-01 00:00 to 02:00 local spans three real hours: 01:00-02:00 happens twice.
        let entries = [timed(local(2026, 10, 31, 22), local(2026, 11, 1, 2))]
        #expect(total(entries, .month, containing: local(2026, 10, 15, 12)) == 7200)
        #expect(total(entries, .month, containing: local(2026, 11, 15, 12)) == 3 * 3600)
    }

    @Test func fallBackEntryCountsElapsedTime() {
        // 2026-11-01 00:30 CDT to 03:30 CST is four real hours.
        let entries = [timed(local(2026, 11, 1, 0, 30), local(2026, 11, 1, 3, 30))]
        #expect(total(entries, .day, containing: local(2026, 11, 1, 12)) == 4 * 3600)
        #expect(DurationFormatter.hoursMinutes(total(entries, .day, containing: local(2026, 11, 1, 12))) == "4:00")
    }

    @Test func springForwardEntryCountsElapsedTime() {
        // 2026-03-08 01:30 CST to 03:30 CDT is one real hour.
        let entries = [timed(local(2026, 3, 8, 1, 30), local(2026, 3, 8, 3, 30))]
        #expect(total(entries, .day, containing: local(2026, 3, 8, 12)) == 3600)
        #expect(DurationFormatter.hoursMinutes(total(entries, .day, containing: local(2026, 3, 8, 12))) == "1:00")
    }

    @Test func totalsArePerClientAndOverall() {
        let entries = [
            timed(1, local(2026, 10, 12, 9), local(2026, 10, 12, 10)),
            timed(2, local(2026, 10, 12, 10), local(2026, 10, 12, 10, 30)),
            timed(1, local(2026, 10, 12, 13), local(2026, 10, 12, 13, 15)),
        ]
        let totals = Totals(
            entries: entries,
            in: Period.day.interval(containing: local(2026, 10, 12, 12), calendar: chicago, weekStartDay: 1),
            now: local(2026, 10, 12, 18))
        #expect(totals.byClient == [1: 4500, 2: 1800])
        #expect(totals.seconds(for: 1) == 4500)
        #expect(totals.seconds(for: 3) == 0)
        #expect(totals.overall == 6300)
    }

    @Test func entriesOutsideTheIntervalCountNothing() {
        let entries = [
            timed(local(2026, 10, 11, 9), local(2026, 10, 11, 10)),
            timed(local(2026, 10, 13, 9), local(2026, 10, 13, 10)),
            timed(local(2026, 10, 13, 9), nil),
        ]
        #expect(total(entries, .day, containing: local(2026, 10, 12, 12), now: local(2026, 10, 13, 11)) == 0)
    }

    @Test func runningEntryCountsUpToNow() {
        let started = local(2026, 10, 14, 14)
        let entries = [timed(started, nil)]
        #expect(total(entries, .day, containing: started, now: started + 600) == 600)
        #expect(total(entries, .day, containing: started, now: started + 1200) == 1200)
        // A running entry from yesterday counts only today's part today.
        #expect(total([timed(local(2026, 10, 13, 23), nil)], .day, containing: started, now: started) == 14 * 3600)
    }

    @Test func readsEntriesFromTheDatabase() throws {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db)
        let first = try defaultClientID(db)
        let second = try secondClient(db)
        try engine.start(clientID: first, at: local(2026, 10, 11, 23))
        try engine.start(clientID: second, at: local(2026, 10, 12, 1))
        try engine.stop(at: local(2026, 10, 12, 2))

        let totals = try Totals(
            for: .day, now: local(2026, 10, 12, 12), calendar: chicago, weekStartDay: 1,
            entries: EntryRepository(database: db))
        #expect(totals.byClient == [first: 3600, second: 3600])
        #expect(totals.overall == 7200)
    }
}

@Suite struct DurationFormatterTests {
    @Test(arguments: [(0, "0:00"), (65, "0:01"), (3_600, "1:00"), (577_500, "160:25"), (-5, "0:00")])
    func hoursMinutes(seconds: Int, text: String) {
        #expect(DurationFormatter.hoursMinutes(seconds) == text)
    }

    @Test(arguments: [(0, "0:00:00"), (65, "0:01:05"), (6_127, "1:42:07"), (577_509, "160:25:09")])
    func hoursMinutesSeconds(seconds: Int, text: String) {
        #expect(DurationFormatter.hoursMinutesSeconds(seconds) == text)
    }
}
