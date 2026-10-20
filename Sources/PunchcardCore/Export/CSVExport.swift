import Foundation
import GRDB

/// A finished export: the text to save and the file name to suggest for it.
public struct CSVDocument: Equatable, Sendable {
    public let fileName: String
    public let text: String
    /// Data rows, not counting the header.
    public let rowCount: Int

    init(fileName: String, header: [String], rows: [[String]]) {
        self.fileName = fileName
        text = CSVWriter.document(header: header, rows: rows)
        rowCount = rows.count
    }
}

/// The two CSV exports. Both are UTF-8 with LF line endings, always carry their header row
/// and leave out the running entry; the Tauri app writes the same files.
///
/// - Entries: `id,client,started_at,ended_at,duration_seconds,duration_hours,note`, one row
///   per entry that touches the range, whole even when it crosses midnight or the range's
///   edge, sorted by start. Timestamps are ISO 8601 with the local UTC offset
///   (`2026-10-15T09:00:00-05:00`); `duration_hours` has two decimals.
/// - Daily summary: `date,client,duration_seconds,duration_hours`, one row per local day and
///   client with time in the range, each entry split at midnight and clipped to the range,
///   sorted by date then client name.
public enum CSVExport {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case entries
        case dailySummary

        public var id: String { rawValue }

        /// The part of the file name before the dates.
        var filePrefix: String {
            switch self {
            case .entries: "punchcard-entries"
            case .dailySummary: "punchcard-daily"
            }
        }
    }

    public static let entriesHeader = ["id", "client", "started_at", "ended_at", "duration_seconds", "duration_hours", "note"]
    public static let dailySummaryHeader = ["date", "client", "duration_seconds", "duration_hours"]

    /// Reads the database and builds the export for `range`, with days taken from `calendar`
    /// and the week start from the settings.
    public static func document(
        kind: Kind, range: ExportRange, from database: Database, now: Date = Date(), calendar: Calendar = .current
    ) throws -> CSVDocument {
        try database.queue.read { db in
            let requested = try range.interval(
                now: now, calendar: calendar, weekStartDay: try SettingsStore.weekStartDay(db))
            let entries = try EntryRepository.completed(overlapping: requested, db)
            // All time covers the days of the first start and the last end; today when there
            // is no entry at all.
            let interval = requested ?? DateInterval(
                start: Period.day.interval(
                    containing: entries.first?.startedAt ?? now, calendar: calendar, weekStartDay: 1).start,
                end: Period.day.interval(
                    containing: entries.compactMap(\.endedAt).max() ?? now, calendar: calendar, weekStartDay: 1).end)
            let clientNames = try DayViewModel.clientNames(db)
            let (header, rows) = switch kind {
            case .entries:
                (entriesHeader, entryRows(entries, clientNames: clientNames, timeZone: calendar.timeZone))
            case .dailySummary:
                (dailySummaryHeader, dailySummaryRows(entries, clientNames: clientNames, interval: interval, calendar: calendar))
            }
            return CSVDocument(
                fileName: fileName(kind: kind, interval: interval, calendar: calendar), header: header, rows: rows)
        }
    }

    /// `punchcard-entries-2026-10-01_2026-10-31.csv`: the first and last day of `interval`.
    public static func fileName(kind: Kind, interval: DateInterval, calendar: Calendar) -> String {
        let lastDay = Period.day.interval(containing: interval.end - 1, calendar: calendar, weekStartDay: 1).start
        return "\(kind.filePrefix)-\(dayString(interval.start, calendar))_\(dayString(lastDay, calendar)).csv"
    }

    /// The entries export of `entries`, which must be completed, in start order.
    public static func entries(_ entries: [Entry], clientNames: [Int64: String], timeZone: TimeZone) -> String {
        CSVWriter.document(header: entriesHeader, rows: entryRows(entries, clientNames: clientNames, timeZone: timeZone))
    }

    static func entryRows(_ entries: [Entry], clientNames: [Int64: String], timeZone: TimeZone) -> [[String]] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return entries
            .filter { !$0.isRunning }
            .sorted { ($0.startedAt, $0.id ?? 0) < ($1.startedAt, $1.id ?? 0) }
            .map { entry in
                let seconds = max(Self.seconds(entry.endedAt!) - Self.seconds(entry.startedAt), 0)
                return [
                    entry.id.map(String.init) ?? "",
                    name(of: entry.clientID, clientNames),
                    formatter.string(from: entry.startedAt),
                    formatter.string(from: entry.endedAt!),
                    String(seconds),
                    hours(seconds),
                    entry.note,
                ]
            }
    }

    /// The daily summary of `entries` within `interval`, which must start and end on local
    /// midnights.
    public static func dailySummary(
        _ entries: [Entry], clientNames: [Int64: String], interval: DateInterval, calendar: Calendar
    ) -> String {
        CSVWriter.document(
            header: dailySummaryHeader,
            rows: dailySummaryRows(entries, clientNames: clientNames, interval: interval, calendar: calendar))
    }

    static func dailySummaryRows(
        _ entries: [Entry], clientNames: [Int64: String], interval: DateInterval, calendar: Calendar
    ) -> [[String]] {
        struct Key: Hashable {
            let day: Date
            let clientID: Int64
        }
        struct Row: Comparable {
            let key: Key
            let name: String
            let seconds: Int

            static func == (lhs: Row, rhs: Row) -> Bool { lhs.key == rhs.key }

            /// By day, then client name, then client ID for two clients whose names compare equal.
            static func < (lhs: Row, rhs: Row) -> Bool {
                if lhs.key.day != rhs.key.day { return lhs.key.day < rhs.key.day }
                switch lhs.name.localizedStandardCompare(rhs.name) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return lhs.key.clientID < rhs.key.clientID
                }
            }
        }
        var seconds: [Key: Int] = [:]
        for entry in entries where !entry.isRunning {
            // Walk the entry's days, adding the part of it inside each; the walk stops at the
            // range's end and starts at its start, which clips the entry to the range.
            var dayStart = Period.day.interval(
                containing: max(entry.startedAt, interval.start), calendar: calendar, weekStartDay: 1).start
            while dayStart < min(entry.endedAt!, interval.end) {
                let day = Period.day.interval(containing: dayStart, calendar: calendar, weekStartDay: 1)
                let clipped = Totals(entries: [entry], in: day, now: entry.endedAt!).seconds(for: entry.clientID)
                if clipped > 0 {
                    seconds[Key(day: day.start, clientID: entry.clientID), default: 0] += clipped
                }
                dayStart = day.end
            }
        }
        return seconds
            .map { Row(key: $0.key, name: name(of: $0.key.clientID, clientNames), seconds: $0.value) }
            .sorted()
            .map { [dayString($0.key.day, calendar), $0.name, String($0.seconds), hours($0.seconds)] }
    }

    /// Hours with two decimals and a dot, whatever the locale.
    static func hours(_ seconds: Int) -> String {
        String(format: "%.2f", Double(seconds) / 3600)
    }

    private static func dayString(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private static func name(of clientID: Int64, _ clientNames: [Int64: String]) -> String {
        clientNames[clientID] ?? "Client \(clientID)"
    }

    private static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }
}
