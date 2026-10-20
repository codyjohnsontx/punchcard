import Foundation

/// What the Settings window's General tab shows and edits, in the units the user sees: the
/// menu bar style, the week start day and the away threshold in whole minutes. The threshold
/// is clamped to 1...120 minutes, the range the `settings` table accepts in seconds, so any
/// value typed into the field is stored valid.
public struct SettingsViewModel: Equatable, Sendable {
    /// One of the seven days the week can start on.
    public struct Weekday: Equatable, Identifiable, Sendable {
        /// ISO numbering: 1 = Monday ... 7 = Sunday, as stored in `week_start_day`.
        public let day: Int
        /// The day's name in the calendar's locale.
        public let name: String

        public var id: Int { day }
    }

    public static let idleThresholdMinutesRange = 1...120

    public var menuBarStyle: SettingsStore.MenuBarStyle
    /// ISO numbering: 1 = Monday ... 7 = Sunday.
    public var weekStartDay: Int {
        didSet { precondition((1...7).contains(weekStartDay), "week start day must be 1...7") }
    }
    /// Minutes idle or asleep before the away prompt; assignments outside 1...120 are clamped.
    public var idleThresholdMinutes: Int {
        didSet { idleThresholdMinutes = Self.clamp(idleThresholdMinutes) }
    }

    public init(menuBarStyle: SettingsStore.MenuBarStyle, weekStartDay: Int, idleThresholdMinutes: Int) {
        self.menuBarStyle = menuBarStyle
        self.weekStartDay = weekStartDay
        self.idleThresholdMinutes = Self.clamp(idleThresholdMinutes)
    }

    /// The defaults a fresh database uses.
    public init() {
        self.init(
            menuBarStyle: SettingsStore.defaultMenuBarStyle, weekStartDay: SettingsStore.defaultWeekStartDay,
            idleThresholdMinutes: SettingsStore.defaultIdleThresholdSeconds / 60)
    }

    /// Reads the current settings. A threshold stored in seconds shows as the nearest minute.
    public static func load(from store: SettingsStore) throws -> SettingsViewModel {
        SettingsViewModel(
            menuBarStyle: try store.menuBarStyle,
            weekStartDay: try store.weekStartDay,
            idleThresholdMinutes: Int((Double(try store.idleThresholdSeconds) / 60).rounded()))
    }

    /// The threshold as the `settings` table stores it.
    public var idleThresholdSeconds: Int { idleThresholdMinutes * 60 }

    /// The week start as `Calendar.firstWeekday` wants it: 1 = Sunday ... 7 = Saturday.
    public var firstWeekday: Int { Calendar.firstWeekday(weekStartDay: weekStartDay) }

    /// The seven days a week can start on, Monday first, named in `calendar`'s locale.
    public static func weekdays(calendar: Calendar = .current) -> [Weekday] {
        (1...7).map { day in
            Weekday(day: day, name: calendar.standaloneWeekdaySymbols[Calendar.firstWeekday(weekStartDay: day) - 1])
        }
    }

    private static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, idleThresholdMinutesRange.lowerBound), idleThresholdMinutesRange.upperBound)
    }
}
