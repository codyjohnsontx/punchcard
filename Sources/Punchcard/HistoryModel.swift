import Foundation
import Observation
import PunchcardCore

/// State of the Entries tab: which day or week is shown, its rows, and the entry being
/// edited or deleted. Reads go straight to the core view models; every write goes through
/// `EntryEditor` and then refreshes the app model so the dropdown's totals follow.
@MainActor @Observable
final class HistoryModel {
    enum Mode: String, CaseIterable, Identifiable {
        case day = "Day"
        case week = "Week"

        var id: String { rawValue }
    }

    /// An entry open in the editor sheet; `original` is nil for a new manual entry.
    struct Editing: Identifiable {
        let id = UUID()
        /// The entry as the editor opened it.
        let original: Entry?
        var draft: EntryDraft

        var entryID: Int64? { original?.id }
        /// The entry runs, so the editor offers to keep it running.
        var wasRunning: Bool { original?.isRunning ?? false }
    }

    let app: AppModel
    var mode: Mode = .day
    /// The day shown, or any day of the week shown.
    var date = Date()
    private(set) var day: DayViewModel?
    private(set) var week: WeekViewModel?
    /// The last failed delete, cleared by the next write that succeeds.
    private var writeError: String?
    /// The last failed read, cleared by the next read that succeeds.
    private var readError: String?
    var error: String? { writeError ?? readError }
    var editing: Editing?
    /// The row awaiting the delete confirmation.
    var deleting: DayViewModel.Row?

    init(app: AppModel) {
        self.app = app
    }

    private var calendar: Calendar { .current }

    /// Re-reads the shown day or week. Called on appear, after every write, and whenever the
    /// app model's snapshot changes, which also happens once a second while a clock runs.
    func reload() {
        guard let database = app.database else { return }
        let now = Date()
        do {
            switch mode {
            case .day: day = try DayViewModel.load(from: database, containing: date, now: now, calendar: calendar)
            case .week: week = try WeekViewModel.load(from: database, containing: date, now: now, calendar: calendar)
            }
            readError = nil
        } catch {
            readError = error.localizedDescription
        }
    }

    func showPrevious() { step(-1) }
    func showNext() { step(1) }
    func showToday() { date = Date() }

    /// Switches to the Day view for `day`, as clicking a day in the Week view does.
    func show(day: Date) {
        mode = .day
        date = day
    }

    private func step(_ count: Int) {
        let component: Calendar.Component = mode == .day ? .day : .weekOfYear
        if let next = calendar.date(byAdding: component, value: count, to: date) {
            date = next
        }
    }

    /// Opens the editor for a new entry on the shown day. In single-client mode the client is
    /// filled in; otherwise the user picks one.
    func addEntry() {
        let clientID = app.snapshot.isSingleClient ? app.snapshot.clients.first?.id : nil
        editing = Editing(original: nil, draft: .manual(clientID: clientID, on: date, calendar: calendar))
    }

    func edit(_ row: DayViewModel.Row) {
        editing = Editing(original: row.entry, draft: EntryDraft(row.entry))
    }

    func save(_ editing: Editing) throws {
        guard let database = app.database else { return }
        try EntryEditor(database: database).save(editing.draft, replacing: editing.original)
        writeError = nil
        didWrite()
    }

    func delete(_ row: DayViewModel.Row) {
        guard let database = app.database else { return }
        do {
            try EntryEditor(database: database).delete(id: row.id)
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
        didWrite()
    }

    private func didWrite() {
        // The dropdown re-reads its totals; its snapshot change then reloads this view too.
        app.refresh()
        reload()
    }

    /// Clients offered by the editor's picker: the active ones, plus the edited entry's own
    /// client when it is archived, so the entry can keep it.
    func clientChoices(including clientID: Int64?) -> [Client] {
        var clients = app.snapshot.clients
        if let clientID, !clients.contains(where: { $0.id == clientID }) {
            let now = Date()
            clients.append(Client(id: clientID, name: app.snapshot.name(of: clientID), archivedAt: now, createdAt: now))
        }
        return clients
    }

    /// How many other entries the draft would overlap if saved.
    func overlapCount(of draft: EntryDraft, excluding id: Int64?) -> Int {
        guard let database = app.database else { return 0 }
        let now = Date()
        let others = (try? EntryRepository(database: database).entries(overlapping: draft.startedAt, draft.endedAt ?? now)) ?? []
        return others.filter { $0.id != id && draft.overlaps($0, now: now) }.count
    }
}
