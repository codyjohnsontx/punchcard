import Foundation
import Observation
import PunchcardCore

/// The app's state: one snapshot of the database that the menu bar label and the dropdown
/// render, refreshed after every write, when the dropdown opens, and once a second while a
/// clock runs. All work happens on the main actor; the database is small enough that every
/// read and write is synchronous.
@MainActor @Observable
final class AppModel {
    private(set) var snapshot: TrackerSnapshot
    /// Why the database could not be opened; the app then shows this and can only quit.
    let openError: String?
    /// The last failed write, cleared by the next write that succeeds.
    private var writeError: String?
    /// The last failed read, cleared by the next read that succeeds.
    private var readError: String?
    var lastError: String? { writeError ?? readError }

    private let database: Database?
    private let engine: TimerEngine?
    private var ticker: Task<Void, Never>?

    init() {
        let now = Date()
        var database: Database?
        var openError: String?
        do {
            database = try Database.open(at: Database.defaultURL())
        } catch {
            openError = error.localizedDescription
        }
        self.database = database
        self.engine = database.map { TimerEngine(database: $0) }
        self.openError = openError
        self.snapshot = Self.emptySnapshot(now: now)
        refresh()
    }

    var label: MenuBarLabel { MenuBarLabel(snapshot) }
    var dropdown: DropdownViewModel { DropdownViewModel(snapshot) }

    /// Re-reads the snapshot and starts or stops the 1-second tick to match.
    func refresh() {
        if let database {
            do {
                snapshot = try TrackerSnapshot.load(from: database)
                readError = nil
            } catch {
                readError = error.localizedDescription
            }
        }
        updateTicker()
    }

    func start(clientID: Int64) {
        perform { try $0.start(clientID: clientID) }
    }

    func stop() {
        perform { try $0.stop() }
    }

    private func perform(_ action: (TimerEngine) throws -> Void) {
        guard let engine else { return }
        do {
            try action(engine)
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
        refresh()
    }

    /// While an entry runs, refresh on each whole second of its elapsed time so the clock
    /// changes exactly when the second does; when nothing runs, no timer fires at all.
    private func updateTicker() {
        guard let running = snapshot.running else {
            ticker?.cancel()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(running.startedAt)
                let untilNextSecond = 1 - elapsed.truncatingRemainder(dividingBy: 1)
                try? await Task.sleep(for: .seconds(untilNextSecond), tolerance: .milliseconds(20))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    private static func emptySnapshot(now: Date) -> TrackerSnapshot {
        let empty = Totals(entries: [], in: DateInterval(start: now, end: now), now: now)
        return TrackerSnapshot(
            clients: [], clientNames: [:], running: nil, now: now,
            menuBarStyle: SettingsStore.defaultMenuBarStyle, today: empty, thisWeek: empty, thisMonth: empty)
    }
}
