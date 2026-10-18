import AppKit
import Foundation
import Observation
import PunchcardCore

/// The app's state: one snapshot of the database that the menu bar label and the dropdown
/// render, refreshed after every write, when the dropdown opens, and once a second while a
/// clock runs. Each tick also feeds the away detector, as do sleep and wake, and a "keep or
/// drop?" alert follows when the user returns. All work happens on the main actor; the
/// database is small enough that every read and write is synchronous.
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
    private var away = AwayDetector(threshold: TimeInterval(SettingsStore.defaultIdleThresholdSeconds))
    private let idle: any IdleSource = SystemIdleSource()
    private var isAskingAway = false

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
        observeSleepAndWake()
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
                self.tickAway()
            }
        }
    }

    private func observeSleepAndWake() {
        let center = NSWorkspace.shared.notificationCenter
        // The model lives as long as the app, so the observers are never removed.
        _ = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        }
        _ = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }
    }

    private func tickAway() {
        updateAwayThreshold()
        if away.tick(now: snapshot.now, idle: idle.secondsSinceLastInput(), running: snapshot.running) != nil {
            askAway()
        }
    }

    private func willSleep() {
        refresh()
        updateAwayThreshold()
        away.willSleep(now: snapshot.now, idle: idle.secondsSinceLastInput(), running: snapshot.running)
    }

    private func didWake() {
        refresh()
        updateAwayThreshold()
        if away.didWake(now: snapshot.now, running: snapshot.running) != nil {
            askAway()
        }
    }

    /// Reads the threshold on every use so a change in the settings applies at once.
    private func updateAwayThreshold() {
        guard let database, let seconds = try? SettingsStore(database: database).idleThresholdSeconds else { return }
        away.threshold = TimeInterval(seconds)
    }

    /// Shows the away alert, or, when it is already up and the prompt was extended, closes it
    /// so the loop asks again with the new times.
    private func askAway() {
        guard !isAskingAway else {
            if NSApp.modalWindow != nil { NSApp.abortModal() }
            return
        }
        isAskingAway = true
        // Run the modal alert from a run loop block, not from this main-queue job: the main
        // queue does not drain inside a run loop nested in one of its own jobs, which would
        // freeze the clock, the ticks and sleep/wake handling while the alert is up.
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated { self?.runAwayAlert() }
        }
    }

    private func runAwayAlert() {
        defer { isAskingAway = false }
        while let shown = away.pending {
            guard let choice = AwayAlert.ask(shown) else { continue }
            // The latest times, should the prompt have been extended as the button was clicked.
            guard let prompt = away.takePending() else { return }
            switch choice {
            case .keep: break
            case .dropAndContinue: perform { try $0.dropContinue(prompt) }
            case .dropAndStop: perform { try $0.dropStop(prompt) }
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
