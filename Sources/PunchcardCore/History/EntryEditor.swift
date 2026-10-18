import Foundation
import GRDB

/// What the entry editor edits: a new manual entry or an existing one. `endedAt` nil means
/// the entry runs; the editor only offers that for the entry that already runs.
public struct EntryDraft: Equatable, Sendable {
    public var clientID: Int64?
    public var startedAt: Date
    public var endedAt: Date?
    public var note: String

    public init(clientID: Int64?, startedAt: Date, endedAt: Date?, note: String = "") {
        self.clientID = clientID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }

    public init(_ entry: Entry) {
        self.init(clientID: entry.clientID, startedAt: entry.startedAt, endedAt: entry.endedAt, note: entry.note)
    }

    /// A one-hour entry on `day` for a new manual entry: 9:00 to 10:00 in `calendar`.
    public static func manual(clientID: Int64?, on day: Date, calendar: Calendar = .current) -> EntryDraft {
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        return EntryDraft(clientID: clientID, startedAt: start, endedAt: end)
    }

    public var isRunning: Bool { endedAt == nil }

    /// Whole seconds, as stored, with the note trimmed.
    public var normalized: EntryDraft {
        EntryDraft(
            clientID: clientID,
            startedAt: TimerEngine.wholeSeconds(startedAt),
            endedAt: endedAt.map(TimerEngine.wholeSeconds),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Throws the first problem that would stop a save: no client, or an end before the start.
    /// An end equal to the start is allowed; the clock can produce such an entry.
    public func validate() throws(EntryEditError) {
        guard clientID != nil else { throw .noClient }
        if let endedAt, endedAt < startedAt { throw .endBeforeStart }
    }

    /// Whether the saved entry would share an instant with `other`.
    public func overlaps(_ other: Entry, now: Date) -> Bool {
        EntryOverlaps.overlap(start: startedAt, end: endedAt, other, now: now)
    }
}

public enum EntryEditError: Error, Equatable, LocalizedError {
    case noClient
    case endBeforeStart
    /// The draft makes this entry run while another entry already runs.
    case anotherEntryRunning
    /// The entry being edited was deleted meanwhile.
    case missing

    public var errorDescription: String? {
        switch self {
        case .noClient: "Choose a client."
        case .endBeforeStart: "End can't be before start."
        case .anotherEntryRunning: "Another entry is already running."
        case .missing: "This entry no longer exists."
        }
    }
}

/// Adds, changes and deletes entries from the History window. Every save validates the draft
/// first; the database rules (one running entry, no negative entry) come back as
/// `EntryEditError` too, so the window always has a message to show.
public struct EntryEditor: Sendable {
    let database: Database
    let now: @Sendable () -> Date

    public init(database: Database, now: @escaping @Sendable () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    /// Inserts `draft` as a new entry, or updates the entry `id` with it, and returns the
    /// entry as stored.
    @discardableResult
    public func save(_ draft: EntryDraft, replacing id: Int64? = nil) throws -> Entry {
        let draft = draft.normalized
        try draft.validate()
        guard let clientID = draft.clientID else { throw EntryEditError.noClient }
        let now = TimerEngine.wholeSeconds(now())
        do {
            return try database.queue.write { db in
                if let id {
                    guard var entry = try Entry.fetchOne(db, key: id) else { throw EntryEditError.missing }
                    entry.clientID = clientID
                    entry.startedAt = draft.startedAt
                    entry.endedAt = draft.endedAt
                    entry.note = draft.note
                    entry.updatedAt = now
                    try entry.update(db)
                    return entry
                }
                return try Entry(
                    clientID: clientID, startedAt: draft.startedAt, endedAt: draft.endedAt, note: draft.note,
                    createdAt: now, updatedAt: now
                ).insertAndFetch(db)
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw EntryEditError.anotherEntryRunning
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_CHECK {
            throw EntryEditError.endBeforeStart
        }
    }

    /// Deletes the entry; deleting one that is already gone is not an error.
    public func delete(id: Int64) throws {
        try EntryRepository(database: database).delete(id: id)
    }
}
