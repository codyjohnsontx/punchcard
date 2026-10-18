import Foundation

/// "You were away" for one entry: the Mac was idle or asleep from `awaySince` until the user
/// came back at `returnedAt`, while the clock kept running.
public struct AwayPrompt: Equatable, Sendable {
    public var entryID: Int64
    public var awaySince: Date
    public var returnedAt: Date

    public init(entryID: Int64, awaySince: Date, returnedAt: Date) {
        self.entryID = entryID
        self.awaySince = awaySince
        self.returnedAt = returnedAt
    }

    /// Whole minutes away, at least 1 (the threshold is never below a minute).
    public var awayMinutes: Int {
        max(Int(returnedAt.timeIntervalSince(awaySince) / 60), 1)
    }

    /// The alert's headline, e.g. "You were away for 23 minutes (since 2:15 PM)."
    public func message(timeFormat: Date.FormatStyle = .init(date: .omitted, time: .shortened)) -> String {
        let minutes = awayMinutes == 1 ? "1 minute" : "\(awayMinutes) minutes"
        return "You were away for \(minutes) (since \(awaySince.formatted(timeFormat)))."
    }
}

/// Decides when to ask "keep or drop?" from three signals: input idle time read on each
/// 1-second tick, sleep and wake notifications, and a gap between ticks (the Mac slept or the
/// process was suspended, even if the sleep notification was missed). It only watches while
/// an entry runs and holds at most one pending prompt: a later away period extends it rather
/// than stacking another dialog. Pure state: every call takes its instant and inputs.
public struct AwayDetector: Sendable {
    /// Input more recent than this means the user is back.
    public static let returnedIdleSeconds: TimeInterval = 5

    /// How long idle or asleep counts as away (`idle_threshold_seconds`).
    public var threshold: TimeInterval
    /// The prompt waiting for an answer, if any.
    public private(set) var pending: AwayPrompt?

    private var entryID: Int64?
    private var entryStart = Date.distantPast
    private var awaySince: Date?
    private var lastTick: Date?

    public init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    /// One tick of the running clock, with `idle` seconds since the last input event. Returns
    /// the pending prompt when it was created or extended, so the caller shows or updates it.
    public mutating func tick(now: Date, idle: TimeInterval, running: Entry?) -> AwayPrompt? {
        guard watch(running) else { return nil }
        defer { lastTick = now }
        if awaySince == nil, let lastTick, now.timeIntervalSince(lastTick) >= threshold {
            awaySince = max(lastTick, entryStart)
        }
        if awaySince == nil, idle >= threshold {
            awaySince = max(now - idle, entryStart)
        }
        guard awaySince != nil, idle < Self.returnedIdleSeconds else { return nil }
        return returned(at: now)
    }

    /// The Mac is about to sleep; it counts as away from the last input on.
    public mutating func willSleep(now: Date, idle: TimeInterval, running: Entry?) {
        guard watch(running), awaySince == nil else { return }
        awaySince = max(now - idle, entryStart)
    }

    /// The Mac woke. Returns the pending prompt when it was created or extended.
    public mutating func didWake(now: Date, running: Entry?) -> AwayPrompt? {
        // With no away start the sleep notification was missed; the next tick's gap catches it.
        guard watch(running), awaySince != nil else { return nil }
        lastTick = now
        return returned(at: now)
    }

    /// Removes and returns the pending prompt once it has been answered.
    public mutating func takePending() -> AwayPrompt? {
        defer { pending = nil }
        return pending
    }

    /// Follows the running entry, starting over when it changes. False when nothing runs.
    private mutating func watch(_ running: Entry?) -> Bool {
        guard let running, let id = running.id else {
            entryID = nil
            awaySince = nil
            lastTick = nil
            return false
        }
        if id != entryID {
            entryID = id
            entryStart = running.startedAt
            awaySince = nil
            lastTick = nil
        }
        return true
    }

    private mutating func returned(at now: Date) -> AwayPrompt? {
        guard let since = awaySince, let entryID else { return nil }
        awaySince = nil
        guard now.timeIntervalSince(since) >= threshold else { return nil }
        guard var prompt = pending else {
            pending = AwayPrompt(entryID: entryID, awaySince: since, returnedAt: now)
            return pending
        }
        // One dialog at a time; a prompt for an entry that no longer runs keeps its own times.
        guard prompt.entryID == entryID else { return nil }
        prompt.awaySince = min(prompt.awaySince, since)
        prompt.returnedAt = max(prompt.returnedAt, now)
        pending = prompt
        return prompt
    }
}
