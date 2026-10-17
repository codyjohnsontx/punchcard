import Foundation

/// Tracked seconds within one interval, per client and overall. Each entry contributes the
/// part of it inside the interval, so an entry crossing midnight (or a week or month
/// boundary) is split between the periods, and a running entry counts up to `now`.
public struct Totals: Equatable, Sendable {
    public var interval: DateInterval
    /// Seconds per client ID; clients with no time in the interval are absent.
    public var byClient: [Int64: Int]

    public var overall: Int { byClient.values.reduce(0, +) }

    public func seconds(for clientID: Int64) -> Int { byClient[clientID] ?? 0 }

    /// Sums `entries` clipped to `interval`, ending a running entry at `now`.
    public init(entries: [Entry], in interval: DateInterval, now: Date) {
        let start = Self.seconds(interval.start)
        let end = Self.seconds(interval.end)
        let now = Self.seconds(now)
        self.interval = interval
        byClient = [:]
        for entry in entries {
            let entryEnd = entry.endedAt.map(Self.seconds) ?? now
            let clipped = min(entryEnd, end) - max(Self.seconds(entry.startedAt), start)
            if clipped > 0 {
                byClient[entry.clientID, default: 0] += clipped
            }
        }
    }

    /// Reads the entries overlapping `interval` and sums them.
    public init(in interval: DateInterval, now: Date, entries: EntryRepository) throws {
        self.init(entries: try entries.entries(overlapping: interval.start, interval.end), in: interval, now: now)
    }

    /// Totals for the `period` containing `now`.
    public init(
        for period: Period, now: Date, calendar: Calendar = .current, weekStartDay: Int, entries: EntryRepository
    ) throws {
        try self.init(
            in: period.interval(containing: now, calendar: calendar, weekStartDay: weekStartDay),
            now: now, entries: entries)
    }

    /// Whole Unix seconds, as the database stores them.
    private static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }
}
