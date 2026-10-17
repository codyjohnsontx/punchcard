import Foundation
import GRDB

/// Typed access to the `settings` key/value table. An absent or unparseable value reads
/// as the default, so the table only ever holds what the user changed.
public struct SettingsStore: Sendable {
    public enum MenuBarStyle: String, Sendable {
        /// The running time, e.g. "● 1:42".
        case time
        /// The clock icon only.
        case icon
    }

    public static let defaultWeekStartDay = 1
    public static let defaultIdleThresholdSeconds = 600
    public static let idleThresholdRange = 60...7200
    public static let defaultMenuBarStyle = MenuBarStyle.time

    let database: Database

    public init(database: Database) {
        self.database = database
    }

    /// First day of the week, ISO numbering: 1 = Monday ... 7 = Sunday. Default Monday.
    public var weekStartDay: Int {
        get throws { try int("week_start_day", in: 1...7) ?? Self.defaultWeekStartDay }
    }

    public func setWeekStartDay(_ day: Int) throws {
        precondition((1...7).contains(day), "week start day must be 1...7")
        try set("week_start_day", String(day))
    }

    /// How long the Mac may be idle or asleep before the away prompt. Default 10 minutes.
    public var idleThresholdSeconds: Int {
        get throws { try int("idle_threshold_seconds", in: Self.idleThresholdRange) ?? Self.defaultIdleThresholdSeconds }
    }

    public func setIdleThresholdSeconds(_ seconds: Int) throws {
        precondition(Self.idleThresholdRange.contains(seconds), "idle threshold out of range")
        try set("idle_threshold_seconds", String(seconds))
    }

    /// What the menu bar shows. Default: the running time.
    public var menuBarStyle: MenuBarStyle {
        get throws { try string("menu_bar_style").flatMap(MenuBarStyle.init(rawValue:)) ?? Self.defaultMenuBarStyle }
    }

    public func setMenuBarStyle(_ style: MenuBarStyle) throws {
        try set("menu_bar_style", style.rawValue)
    }

    /// When first-launch tasks (such as registering the login item) ran; nil until then.
    public var onboardedAt: Date? {
        get throws { try string("onboarded_at").flatMap(Int64.init).map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    }

    public func setOnboardedAt(_ date: Date) throws {
        try set("onboarded_at", String(Int64(date.timeIntervalSince1970)))
    }

    private func string(_ key: String) throws -> String? {
        try database.queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    private func int(_ key: String, in range: ClosedRange<Int>) throws -> Int? {
        try string(key).flatMap(Int.init).flatMap { range.contains($0) ? $0 : nil }
    }

    private func set(_ key: String, _ value: String) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key, value])
        }
    }
}
