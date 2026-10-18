import Foundation
import GRDB

/// One week of the History window's Entries tab: seven day columns, a row per client with
/// time in the week, and the week's totals. Entries are clipped to each day, so one crossing
/// midnight counts toward both days, and the week only holds its own part of an entry
/// crossing the week boundary.
public struct WeekViewModel: Equatable, Sendable {
    public struct Day: Equatable, Identifiable, Sendable {
        public var id: Date { interval.start }
        public let interval: DateInterval
        /// Seconds tracked on this day, every client together.
        public let seconds: Int
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public let id: Int64
        public let name: String
        /// Seconds per day, in the order of `days`.
        public let seconds: [Int]
        public var total: Int { seconds.reduce(0, +) }
    }

    /// The week, `[start, end)`, starting on the configured week start day.
    public let interval: DateInterval
    public let now: Date
    public let days: [Day]
    /// Clients with time in the week, sorted by name.
    public let rows: [Row]
    public var totalSeconds: Int { days.reduce(0) { $0 + $1.seconds } }

    /// Whether the week shows a row per client above its totals: always, unless at most one
    /// client is active (`TrackerSnapshot.isSingleClient`) and only one has time this week.
    public func showsClientRows(singleClient: Bool) -> Bool {
        !singleClient || rows.count > 1
    }

    public init(entries: [Entry], clientNames: [Int64: String], interval: DateInterval, now: Date, calendar: Calendar) {
        self.interval = interval
        self.now = now
        var totals: [Totals] = []
        var start = interval.start
        while start < interval.end {
            let day = Period.day.interval(containing: start, calendar: calendar, weekStartDay: 1)
            totals.append(Totals(entries: entries, in: day, now: now))
            start = day.end
        }
        days = totals.map { Day(interval: $0.interval, seconds: $0.overall) }
        let name = { (id: Int64) in clientNames[id] ?? "Client \(id)" }
        rows = Set(totals.flatMap { $0.byClient.keys })
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
            .map { id in Row(id: id, name: name(id), seconds: totals.map { $0.seconds(for: id) }) }
    }

    /// Reads the week containing `date`, with the week start from the settings.
    public static func load(
        from database: Database, containing date: Date, now: Date = Date(), calendar: Calendar = .current
    ) throws -> WeekViewModel {
        try database.queue.read { db in
            let interval = Period.week.interval(
                containing: date, calendar: calendar, weekStartDay: try SettingsStore.weekStartDay(db))
            return WeekViewModel(
                entries: try EntryRepository.entries(overlapping: interval.start, interval.end, db),
                clientNames: try DayViewModel.clientNames(db), interval: interval, now: now, calendar: calendar)
        }
    }
}
