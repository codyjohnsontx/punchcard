import Foundation

/// A day, week or month in the viewer's calendar and time zone. Its interval is half-open,
/// `[start, end)`, so DST days are 23 or 25 hours long, which is right because durations
/// are differences of absolute instants.
public enum Period: Sendable, CaseIterable {
    case day
    case week
    case month

    /// The interval of this period containing `date`. `weekStartDay` uses the settings'
    /// ISO numbering, 1 = Monday ... 7 = Sunday, and only affects `.week`.
    public func interval(containing date: Date, calendar: Calendar = .current, weekStartDay: Int) -> DateInterval {
        precondition((1...7).contains(weekStartDay), "week start day must be 1...7")
        var calendar = calendar
        // Calendar counts weekdays 1 = Sunday ... 7 = Saturday.
        calendar.firstWeekday = weekStartDay % 7 + 1
        let component: Calendar.Component = switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            preconditionFailure("calendar has no \(component) interval for \(date)")
        }
        return interval
    }
}
