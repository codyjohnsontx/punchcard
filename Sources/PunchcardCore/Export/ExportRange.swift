import Foundation

/// Which entries an export covers, as the Export tab offers them. A range resolves to the
/// half-open `[start, end)` interval of whole local days it names; `.allTime` resolves to nil
/// and the export then takes its bounds from the data.
public enum ExportRange: Hashable, Sendable {
    case thisWeek
    case thisMonth
    case lastMonth
    case allTime
    /// Every day from `from` through `through`, both inclusive; only their calendar days
    /// matter, not their times of day.
    case days(from: Date, through: Date)

    public func interval(now: Date, calendar: Calendar, weekStartDay: Int) throws(ExportError) -> DateInterval? {
        switch self {
        case .thisWeek:
            return Period.week.interval(containing: now, calendar: calendar, weekStartDay: weekStartDay)
        case .thisMonth:
            return Period.month.interval(containing: now, calendar: calendar, weekStartDay: weekStartDay)
        case .lastMonth:
            let thisMonth = Period.month.interval(containing: now, calendar: calendar, weekStartDay: weekStartDay)
            return Period.month.interval(containing: thisMonth.start - 1, calendar: calendar, weekStartDay: weekStartDay)
        case .allTime:
            return nil
        case .days(let from, let through):
            let first = Period.day.interval(containing: from, calendar: calendar, weekStartDay: weekStartDay)
            let last = Period.day.interval(containing: through, calendar: calendar, weekStartDay: weekStartDay)
            guard first.start <= last.start else { throw .endBeforeStart }
            return DateInterval(start: first.start, end: last.end)
        }
    }
}

public enum ExportError: Error, Equatable, LocalizedError {
    /// A custom range whose end day is before its start day.
    case endBeforeStart

    public var errorDescription: String? {
        switch self {
        case .endBeforeStart: "The end date must not be before the start date."
        }
    }
}
