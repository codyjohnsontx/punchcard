import Foundation
import GRDB

/// Everything the menu bar label and the dropdown show, read from the database in one
/// transaction at one instant, so the label, the client rows and the totals never disagree.
public struct TrackerSnapshot: Equatable, Sendable {
    /// Active (unarchived) clients, sorted by name.
    public var clients: [Client]
    /// The name of every client, archived ones included, for the running entry and totals.
    public var clientNames: [Int64: String]
    /// The running entry, if any.
    public var running: Entry?
    /// The instant the snapshot was taken; the running clock and totals count up to it.
    public var now: Date
    public var menuBarStyle: SettingsStore.MenuBarStyle
    public var today: Totals
    public var thisWeek: Totals
    public var thisMonth: Totals

    public init(
        clients: [Client], clientNames: [Int64: String], running: Entry?, now: Date,
        menuBarStyle: SettingsStore.MenuBarStyle, today: Totals, thisWeek: Totals, thisMonth: Totals
    ) {
        self.clients = clients
        self.clientNames = clientNames
        self.running = running
        self.now = now
        self.menuBarStyle = menuBarStyle
        self.today = today
        self.thisWeek = thisWeek
        self.thisMonth = thisMonth
    }

    /// Reads the snapshot at `now`, with the day, week and month taken from `calendar` and the
    /// week start from the settings.
    public static func load(from database: Database, now: Date = Date(), calendar: Calendar = .current) throws -> TrackerSnapshot {
        try database.queue.read { db in
            let allClients = try ClientRepository.all(includeArchived: true, db)
            let weekStartDay = try SettingsStore.weekStartDay(db)
            let intervals = Period.allCases.map { $0.interval(containing: now, calendar: calendar, weekStartDay: weekStartDay) }
            // One query covers all three periods; Totals clips each entry to its interval.
            let span = DateInterval(
                start: intervals.map(\.start).min() ?? now, end: intervals.map(\.end).max() ?? now)
            let entries = try EntryRepository.entries(overlapping: span.start, span.end, db)
            let totals = intervals.map { Totals(entries: entries, in: $0, now: now) }
            return TrackerSnapshot(
                clients: allClients.filter { $0.archivedAt == nil },
                clientNames: Dictionary(uniqueKeysWithValues: allClients.compactMap { client in
                    client.id.map { ($0, client.name) }
                }),
                running: try EntryRepository.running(db),
                now: now,
                menuBarStyle: try SettingsStore.menuBarStyle(db),
                today: totals[0], thisWeek: totals[1], thisMonth: totals[2])
        }
    }

    /// True while at most one client is active. The dropdown then shows a single Start/Stop
    /// button and no per-client split, and the menu bar shows no client name.
    public var isSingleClient: Bool { clients.count <= 1 }

    /// Whole seconds the running entry has run at `now`; 0 when stopped or if the clock moved
    /// back past the start.
    public var runningSeconds: Int {
        guard let running else { return 0 }
        return max(Int((now.timeIntervalSince(running.startedAt)).rounded(.down)), 0)
    }

    /// The name of the client whose clock runs, or nil when stopped.
    public var runningClientName: String? {
        running.map { name(of: $0.clientID) }
    }

    /// A client's name, archived or not. Falls back to the ID for a row the snapshot missed.
    public func name(of clientID: Int64) -> String {
        clientNames[clientID] ?? "Client \(clientID)"
    }
}
