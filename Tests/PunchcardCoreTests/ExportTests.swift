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

private let names: [Int64: String] = [1: "Acme", 2: "Globex", 3: "initech"]

private func entry(_ id: Int64, _ clientID: Int64, _ start: Date, _ end: Date?, note: String = "") -> Entry {
    Entry(id: id, clientID: clientID, startedAt: start, endedAt: end, note: note, createdAt: start, updatedAt: start)
}

private func days(_ start: Date, _ end: Date) -> DateInterval {
    DateInterval(
        start: Period.day.interval(containing: start, calendar: chicago, weekStartDay: 1).start,
        end: Period.day.interval(containing: end, calendar: chicago, weekStartDay: 1).end)
}

private func lines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

@Suite struct CSVWriterTests {
    @Test func quotesFieldsHoldingCommasQuotesOrLineBreaks() {
        #expect(CSVWriter.field("plain") == "plain")
        #expect(CSVWriter.field("") == "")
        #expect(CSVWriter.field("a,b") == "\"a,b\"")
        #expect(CSVWriter.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVWriter.field("two\nlines") == "\"two\nlines\"")
        #expect(CSVWriter.field("old\r\nmac\r") == "\"old\r\nmac\r\"")
    }

    @Test func documentHasHeaderAndLFLineEndings() {
        let text = CSVWriter.document(header: ["a", "b"], rows: [["1", "x,y"], ["2", ""]])
        #expect(text == "a,b\n1,\"x,y\"\n2,\n")
        #expect(CSVWriter.document(header: ["a"], rows: []) == "a\n")
    }
}

@Suite struct EntriesExportTests {
    @Test func writesOneRowPerEntryInStartOrderWithLocalOffsets() {
        let later = entry(7, 2, local(2026, 10, 15, 13), local(2026, 10, 15, 14, 45))
        let earlier = entry(5, 1, local(2026, 10, 15, 9), local(2026, 10, 15, 11, 30), note: "Design review")
        let text = CSVExport.entries([later, earlier], clientNames: names, timeZone: chicago.timeZone)
        #expect(lines(text) == [
            "id,client,started_at,ended_at,duration_seconds,duration_hours,note",
            "5,Acme,2026-10-15T09:00:00-05:00,2026-10-15T11:30:00-05:00,9000,2.50,Design review",
            "7,Globex,2026-10-15T13:00:00-05:00,2026-10-15T14:45:00-05:00,6300,1.75,",
            "",
        ])
    }

    @Test func quotesANoteWithAQuoteACommaAndANewline() {
        let note = "Call with \"Bob\", then\nwrite-up"
        let one = entry(1, 1, local(2026, 10, 15, 9), local(2026, 10, 15, 10), note: note)
        let text = CSVExport.entries([one], clientNames: names, timeZone: chicago.timeZone)
        #expect(text == """
            id,client,started_at,ended_at,duration_seconds,duration_hours,note
            1,Acme,2026-10-15T09:00:00-05:00,2026-10-15T10:00:00-05:00,3600,1.00,"Call with ""Bob"", then
            write-up"

            """)
    }

    @Test func midnightCrossingEntryIsOneRowAndTheRunningEntryIsLeftOut() {
        let acrossMidnight = entry(10, 2, local(2026, 10, 13, 23), local(2026, 10, 14, 1))
        let running = entry(11, 1, local(2026, 10, 14, 15), nil)
        let text = CSVExport.entries([acrossMidnight, running], clientNames: names, timeZone: chicago.timeZone)
        #expect(lines(text) == [
            "id,client,started_at,ended_at,duration_seconds,duration_hours,note",
            "10,Globex,2026-10-13T23:00:00-05:00,2026-10-14T01:00:00-05:00,7200,2.00,",
            "",
        ])
    }

    @Test func offsetsFollowTheClockAcrossDSTChanges() {
        // Fall back: 00:30 CDT to 03:30 CST is four hours.
        let fallBack = entry(1, 1, local(2026, 11, 1, 0, 30), local(2026, 11, 1, 3, 30))
        // Spring forward: 01:30 CST to 03:30 CDT is one hour.
        let springForward = entry(2, 1, local(2026, 3, 8, 1, 30), local(2026, 3, 8, 3, 30))
        let text = CSVExport.entries([fallBack, springForward], clientNames: names, timeZone: chicago.timeZone)
        #expect(lines(text) == [
            "id,client,started_at,ended_at,duration_seconds,duration_hours,note",
            "2,Acme,2026-03-08T01:30:00-06:00,2026-03-08T03:30:00-05:00,3600,1.00,",
            "1,Acme,2026-11-01T00:30:00-05:00,2026-11-01T03:30:00-06:00,14400,4.00,",
            "",
        ])
    }

    @Test func hoursHaveTwoDecimalsAndADot() {
        #expect(CSVExport.hours(0) == "0.00")
        #expect(CSVExport.hours(65) == "0.02")
        #expect(CSVExport.hours(3600) == "1.00")
        #expect(CSVExport.hours(577_500) == "160.42")
    }
}

@Suite struct DailySummaryExportTests {
    @Test func splitsAMidnightCrossingEntryBetweenItsDaysAndSortsByDateThenName() {
        let acrossMidnight = entry(10, 2, local(2026, 10, 13, 23), local(2026, 10, 14, 1))
        let morning = entry(11, 1, local(2026, 10, 14, 9), local(2026, 10, 14, 11, 30))
        let afternoon = entry(12, 1, local(2026, 10, 14, 13), local(2026, 10, 14, 13, 30))
        let lowercase = entry(13, 3, local(2026, 10, 14, 14), local(2026, 10, 14, 14, 15))
        let running = entry(14, 1, local(2026, 10, 14, 15), nil)
        let text = CSVExport.dailySummary(
            [running, lowercase, afternoon, morning, acrossMidnight], clientNames: names,
            interval: days(local(2026, 10, 12, 12), local(2026, 10, 14, 12)), calendar: chicago)
        #expect(lines(text) == [
            "date,client,duration_seconds,duration_hours",
            "2026-10-13,Globex,3600,1.00",
            "2026-10-14,Acme,10800,3.00",
            "2026-10-14,Globex,3600,1.00",
            "2026-10-14,initech,900,0.25",
            "",
        ])
    }

    @Test func clipsEntriesToTheRange() {
        let acrossMidnight = entry(10, 2, local(2026, 10, 13, 23), local(2026, 10, 14, 1))
        let text = CSVExport.dailySummary(
            [acrossMidnight], clientNames: names, interval: days(local(2026, 10, 14, 12), local(2026, 10, 14, 12)),
            calendar: chicago)
        #expect(lines(text) == ["date,client,duration_seconds,duration_hours", "2026-10-14,Globex,3600,1.00", ""])
    }

    @Test func countsDSTDaysByTheirRealLength() {
        let fallBack = entry(1, 1, local(2026, 11, 1, 0, 30), local(2026, 11, 1, 3, 30))
        let text = CSVExport.dailySummary(
            [fallBack], clientNames: names, interval: days(local(2026, 11, 1, 12), local(2026, 11, 1, 12)),
            calendar: chicago)
        #expect(lines(text) == ["date,client,duration_seconds,duration_hours", "2026-11-01,Acme,14400,4.00", ""])
    }

    @Test func emptyRangeIsHeaderOnly() {
        let text = CSVExport.dailySummary(
            [], clientNames: names, interval: days(local(2026, 10, 1, 12), local(2026, 10, 31, 12)), calendar: chicago)
        #expect(text == "date,client,duration_seconds,duration_hours\n")
        #expect(CSVExport.entries([], clientNames: names, timeZone: chicago.timeZone)
            == "id,client,started_at,ended_at,duration_seconds,duration_hours,note\n")
    }
}

@Suite struct ExportRangeTests {
    private let now = local(2026, 10, 14, 15, 30)  // a Wednesday

    @Test func presetsResolveToWholeLocalPeriods() throws {
        #expect(try ExportRange.thisWeek.interval(now: now, calendar: chicago, weekStartDay: 1)
            == days(local(2026, 10, 12, 0), local(2026, 10, 18, 0)))
        #expect(try ExportRange.thisWeek.interval(now: now, calendar: chicago, weekStartDay: 7)
            == days(local(2026, 10, 11, 0), local(2026, 10, 17, 0)))
        #expect(try ExportRange.thisMonth.interval(now: now, calendar: chicago, weekStartDay: 1)
            == days(local(2026, 10, 1, 0), local(2026, 10, 31, 0)))
        #expect(try ExportRange.lastMonth.interval(now: now, calendar: chicago, weekStartDay: 1)
            == days(local(2026, 9, 1, 0), local(2026, 9, 30, 0)))
        #expect(try ExportRange.lastMonth.interval(now: local(2026, 1, 10, 9), calendar: chicago, weekStartDay: 1)
            == days(local(2025, 12, 1, 0), local(2025, 12, 31, 0)))
        #expect(try ExportRange.allTime.interval(now: now, calendar: chicago, weekStartDay: 1) == nil)
    }

    @Test func customRangeCoversWholeDaysAndRejectsAnEndBeforeTheStart() throws {
        let range = ExportRange.days(from: local(2026, 10, 5, 17), through: local(2026, 10, 9, 8))
        #expect(try range.interval(now: now, calendar: chicago, weekStartDay: 1)
            == days(local(2026, 10, 5, 0), local(2026, 10, 9, 0)))
        let oneDay = ExportRange.days(from: local(2026, 10, 5, 17), through: local(2026, 10, 5, 8))
        #expect(try oneDay.interval(now: now, calendar: chicago, weekStartDay: 1)
            == days(local(2026, 10, 5, 0), local(2026, 10, 5, 0)))
        let backwards = ExportRange.days(from: local(2026, 10, 9, 0), through: local(2026, 10, 8, 23))
        #expect(throws: ExportError.endBeforeStart) {
            try backwards.interval(now: now, calendar: chicago, weekStartDay: 1)
        }
    }

    @Test func fileNamesCarryTheFirstAndLastDay() {
        let october = days(local(2026, 10, 1, 0), local(2026, 10, 31, 0))
        #expect(CSVExport.fileName(kind: .entries, interval: october, calendar: chicago)
            == "punchcard-entries-2026-10-01_2026-10-31.csv")
        #expect(CSVExport.fileName(kind: .dailySummary, interval: october, calendar: chicago)
            == "punchcard-daily-2026-10-01_2026-10-31.csv")
    }
}

@Suite struct ExportDocumentTests {
    private let now = local(2026, 10, 14, 15, 30)

    private func database() throws -> (Database, Int64, Int64) {
        let database = try Database.inMemory()
        let clients = ClientRepository(database: database)
        let acme = try clients.all().first!.id!  // the seeded Default client, renamed
        _ = try clients.update(Client(id: acme, name: "Acme", createdAt: now))
        let globex = try clients.insert(name: "Globex", at: now).id!
        let entries = EntryRepository(database: database)
        try entries.insert(entry(nil, acme, local(2026, 9, 30, 23), local(2026, 10, 1, 1)))
        try entries.insert(entry(nil, globex, local(2026, 10, 13, 9), local(2026, 10, 13, 10, 15), note: "a, b\nc"))
        try entries.insert(entry(nil, acme, local(2026, 10, 14, 15), nil))
        return (database, acme, globex)
    }

    private func entry(_ id: Int64?, _ clientID: Int64, _ start: Date, _ end: Date?, note: String = "") -> Entry {
        Entry(id: id, clientID: clientID, startedAt: start, endedAt: end, note: note, createdAt: start, updatedAt: start)
    }

    @Test func thisMonthEntriesIncludeTheEntryTouchingTheMonthAndNotTheRunningOne() throws {
        let (database, _, _) = try database()
        let document = try CSVExport.document(kind: .entries, range: .thisMonth, from: database, now: now, calendar: chicago)
        #expect(document.fileName == "punchcard-entries-2026-10-01_2026-10-31.csv")
        #expect(document.rowCount == 2)
        #expect(lines(document.text) == [
            "id,client,started_at,ended_at,duration_seconds,duration_hours,note",
            "1,Acme,2026-09-30T23:00:00-05:00,2026-10-01T01:00:00-05:00,7200,2.00,",
            "2,Globex,2026-10-13T09:00:00-05:00,2026-10-13T10:15:00-05:00,4500,1.25,\"a, b",
            "c\"",
            "",
        ])
    }

    @Test func thisMonthSummaryOnlyCountsTheMonthsPartOfAnEntry() throws {
        let (database, _, _) = try database()
        let document = try CSVExport.document(
            kind: .dailySummary, range: .thisMonth, from: database, now: now, calendar: chicago)
        #expect(document.fileName == "punchcard-daily-2026-10-01_2026-10-31.csv")
        #expect(lines(document.text) == [
            "date,client,duration_seconds,duration_hours",
            "2026-10-01,Acme,3600,1.00",
            "2026-10-13,Globex,4500,1.25",
            "",
        ])
    }

    @Test func lastMonthIsHeaderOnlyWhenNothingTouchesIt() throws {
        let (database, _, _) = try database()
        let document = try CSVExport.document(
            kind: .dailySummary, range: .days(from: local(2026, 8, 1, 0), through: local(2026, 8, 31, 0)),
            from: database, now: now, calendar: chicago)
        #expect(document.text == "date,client,duration_seconds,duration_hours\n")
        #expect(document.rowCount == 0)
        #expect(document.fileName == "punchcard-daily-2026-08-01_2026-08-31.csv")
    }

    @Test func allTimeSpansTheFirstStartToTheLastEnd() throws {
        let (database, _, _) = try database()
        let document = try CSVExport.document(kind: .dailySummary, range: .allTime, from: database, now: now, calendar: chicago)
        #expect(document.fileName == "punchcard-daily-2026-09-30_2026-10-13.csv")
        #expect(lines(document.text) == [
            "date,client,duration_seconds,duration_hours",
            "2026-09-30,Acme,3600,1.00",
            "2026-10-01,Acme,3600,1.00",
            "2026-10-13,Globex,4500,1.25",
            "",
        ])
    }

    @Test func allTimeWithNoEntriesIsTodayAndHeaderOnly() throws {
        let database = try Database.inMemory()
        let document = try CSVExport.document(kind: .entries, range: .allTime, from: database, now: now, calendar: chicago)
        #expect(document.fileName == "punchcard-entries-2026-10-14_2026-10-14.csv")
        #expect(document.rowCount == 0)
    }

    @Test func thisWeekFollowsTheWeekStartSetting() throws {
        let (database, acme, _) = try database()
        try EntryRepository(database: database).insert(entry(nil, acme, local(2026, 10, 11, 9), local(2026, 10, 11, 10)))  // Sunday
        let monday = try CSVExport.document(kind: .entries, range: .thisWeek, from: database, now: now, calendar: chicago)
        #expect(monday.fileName == "punchcard-entries-2026-10-12_2026-10-18.csv")
        #expect(monday.rowCount == 1)
        try SettingsStore(database: database).setWeekStartDay(7)
        let sunday = try CSVExport.document(kind: .entries, range: .thisWeek, from: database, now: now, calendar: chicago)
        #expect(sunday.fileName == "punchcard-entries-2026-10-11_2026-10-17.csv")
        #expect(sunday.rowCount == 2)
    }
}
