import Foundation
import GRDB

/// One day of the History window's Entries tab: every entry that touches the day, in start
/// order, with the part of each inside the day and the day's total. Pure data; the view
/// formats dates in the viewer's locale.
public struct DayViewModel: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public let id: Int64
        public let entry: Entry
        public let clientName: String
        /// Seconds of the entry inside this day; the day's total is the sum of these.
        public let secondsInDay: Int
        /// Seconds of the whole entry, counted up to `now` while it runs.
        public let seconds: Int
        /// The entry started on an earlier day.
        public let startsBeforeDay: Bool
        /// The entry ends on a later day, or still runs past midnight.
        public let endsAfterDay: Bool
        /// The entry shares an instant with another entry (on any day).
        public let overlaps: Bool

        public var isRunning: Bool { entry.isRunning }
        /// Only part of the entry falls on this day.
        public var isPartial: Bool { startsBeforeDay || endsAfterDay }
    }

    /// The day, `[start, end)`.
    public let interval: DateInterval
    public let now: Date
    public let rows: [Row]
    /// Seconds tracked on this day, every client together.
    public let totalSeconds: Int

    /// Builds the day from `entries`, which may include entries outside the day (they only
    /// feed the overlap flags). An entry belongs to the day when it starts in it or runs into
    /// it; one that ends exactly at the day's start belongs to the day before.
    public init(entries: [Entry], clientNames: [Int64: String], interval: DateInterval, now: Date) {
        self.interval = interval
        self.now = now
        let overlapping = EntryOverlaps.ids(in: entries, now: now)
        rows = entries
            .filter { entry in
                entry.id != nil && entry.startedAt < interval.end
                    && (entry.startedAt >= interval.start || (entry.endedAt ?? now) > interval.start)
            }
            .sorted { ($0.startedAt, $0.id!) < ($1.startedAt, $1.id!) }
            .map { entry in
                let end = entry.endedAt ?? now
                return Row(
                    id: entry.id!,
                    entry: entry,
                    clientName: clientNames[entry.clientID] ?? "Client \(entry.clientID)",
                    secondsInDay: Totals(entries: [entry], in: interval, now: now).overall,
                    seconds: max(Self.seconds(end) - Self.seconds(entry.startedAt), 0),
                    startsBeforeDay: entry.startedAt < interval.start,
                    endsAfterDay: end > interval.end,
                    overlaps: overlapping.contains(entry.id!))
            }
        totalSeconds = rows.reduce(0) { $0 + $1.secondsInDay }
    }

    /// Reads the day containing `date` from the database. Entries that overlap one of the
    /// day's entries on another day are read too, so the overlap flags are complete.
    public static func load(
        from database: Database, containing date: Date, now: Date = Date(), calendar: Calendar = .current
    ) throws -> DayViewModel {
        let interval = Period.day.interval(containing: date, calendar: calendar, weekStartDay: 1)
        return try database.queue.read { db in
            var entries = try EntryRepository.entries(overlapping: interval.start, interval.end, db)
            let span = DateInterval(
                start: min(entries.map(\.startedAt).min() ?? interval.start, interval.start),
                end: max(entries.map { $0.endedAt ?? now }.max() ?? interval.end, interval.end))
            if span != interval {
                entries = try EntryRepository.entries(overlapping: span.start, span.end, db)
            }
            return DayViewModel(
                entries: entries, clientNames: try clientNames(db), interval: interval, now: now)
        }
    }

    static func clientNames(_ db: GRDB.Database) throws -> [Int64: String] {
        Dictionary(uniqueKeysWithValues: try ClientRepository.all(includeArchived: true, db).compactMap { client in
            client.id.map { ($0, client.name) }
        })
    }

    private static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }
}
