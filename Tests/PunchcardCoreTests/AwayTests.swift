import Foundation
@testable import PunchcardCore
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let threshold: TimeInterval = 600

private func at(_ seconds: TimeInterval) -> Date { start + seconds }

private func runningEntry(id: Int64 = 1, startedAt: Date = start) -> Entry {
    Entry(id: id, clientID: 1, startedAt: startedAt, createdAt: startedAt, updatedAt: startedAt)
}

/// Feeds one tick a second from `from` up to `to` (inclusive), with the idle time growing
/// from `idleAtFrom`, and collects every prompt the detector returns.
private func ticks(_ detector: inout AwayDetector, from: TimeInterval, to: TimeInterval,
                   idleAtFrom: TimeInterval = 0, running: Entry = runningEntry()) -> [AwayPrompt] {
    stride(from: from, through: to, by: 1).compactMap { second in
        detector.tick(now: at(second), idle: idleAtFrom + (second - from), running: running)
    }
}

@Suite struct AwayDetectorTests {
    @Test func idleAboveThresholdThenReturnPromptsOnce() {
        var detector = AwayDetector(threshold: threshold)
        // Active for a minute, idle for 15 minutes, then back for a minute.
        var prompts = ticks(&detector, from: 0, to: 60)
        prompts += ticks(&detector, from: 61, to: 960, idleAtFrom: 1)
        prompts += ticks(&detector, from: 961, to: 1020)

        let expected = AwayPrompt(entryID: 1, awaySince: at(60), returnedAt: at(961))
        #expect(prompts == [expected])
        #expect(detector.pending == expected)
        #expect(expected.awayMinutes == 15)
    }

    @Test func idleBelowThresholdNeverPrompts() {
        var detector = AwayDetector(threshold: threshold)
        var prompts = ticks(&detector, from: 0, to: 60)
        prompts += ticks(&detector, from: 61, to: 659, idleAtFrom: 1)
        prompts += ticks(&detector, from: 660, to: 720)

        #expect(prompts.isEmpty)
        #expect(detector.pending == nil)
    }

    @Test func sleepThenWakePastThresholdPromptsFromSleepTime() {
        var detector = AwayDetector(threshold: threshold)
        _ = ticks(&detector, from: 0, to: 100)
        detector.willSleep(now: at(100), idle: 0, running: runningEntry())
        let prompt = detector.didWake(now: at(1300), running: runningEntry())

        let expected = AwayPrompt(entryID: 1, awaySince: at(100), returnedAt: at(1300))
        #expect(prompt == expected)
        // The tick after wake sees the gap but the away period was already reported.
        #expect(ticks(&detector, from: 1301, to: 1310).isEmpty)
        #expect(detector.pending == expected)
    }

    @Test func sleepShorterThanThresholdDoesNotPrompt() {
        var detector = AwayDetector(threshold: threshold)
        _ = ticks(&detector, from: 0, to: 100)
        detector.willSleep(now: at(100), idle: 0, running: runningEntry())
        #expect(detector.didWake(now: at(400), running: runningEntry()) == nil)
        #expect(ticks(&detector, from: 401, to: 410).isEmpty)
    }

    @Test func tickGapPromptsFromLastTick() {
        var detector = AwayDetector(threshold: threshold)
        _ = ticks(&detector, from: 0, to: 100)
        // No sleep notification: the next tick arrives 20 minutes later, user already active.
        let prompt = detector.tick(now: at(1300), idle: 0, running: runningEntry())

        #expect(prompt == AwayPrompt(entryID: 1, awaySince: at(100), returnedAt: at(1300)))
    }

    @Test func tickGapWaitsForTheUserToReturn() {
        var detector = AwayDetector(threshold: threshold)
        _ = ticks(&detector, from: 0, to: 100)
        // Woke without input (the lid opened, nobody touched anything yet).
        #expect(ticks(&detector, from: 1300, to: 1310, idleAtFrom: 30).isEmpty)
        let prompts = ticks(&detector, from: 1311, to: 1320)

        #expect(prompts == [AwayPrompt(entryID: 1, awaySince: at(100), returnedAt: at(1311))])
    }

    @Test func secondAwayPeriodWhilePendingExtendsThePrompt() {
        var detector = AwayDetector(threshold: threshold)
        _ = ticks(&detector, from: 0, to: 60)
        _ = ticks(&detector, from: 61, to: 960, idleAtFrom: 1)
        let first = ticks(&detector, from: 961, to: 1000)
        // Still unanswered, away again for 20 minutes.
        _ = ticks(&detector, from: 1001, to: 2200, idleAtFrom: 1)
        let second = ticks(&detector, from: 2201, to: 2210)

        #expect(first == [AwayPrompt(entryID: 1, awaySince: at(60), returnedAt: at(961))])
        let extended = AwayPrompt(entryID: 1, awaySince: at(60), returnedAt: at(2201))
        #expect(second == [extended])
        #expect(detector.takePending() == extended)
        #expect(detector.pending == nil)
    }

    @Test func idleBeforeTheEntryStartedIsNotAway() {
        // Started from the menu bar after an hour without keyboard input elsewhere.
        var detector = AwayDetector(threshold: threshold)
        let entry = runningEntry(startedAt: at(0))
        var prompts = ticks(&detector, from: 0, to: 300, idleAtFrom: 3600, running: entry)
        prompts += ticks(&detector, from: 301, to: 310, running: entry)
        #expect(prompts.isEmpty)
    }

    @Test func nothingRunningIsNeverAway() {
        var detector = AwayDetector(threshold: threshold)
        detector.willSleep(now: at(0), idle: 0, running: nil)
        #expect(detector.didWake(now: at(3600), running: nil) == nil)
        #expect(detector.tick(now: at(3601), idle: 0, running: nil) == nil)
    }

    @Test func aNewEntryStartsOver() {
        var detector = AwayDetector(threshold: threshold)
        _ = ticks(&detector, from: 0, to: 100)
        // A new entry starts 20 minutes later: no gap against the old entry's ticks.
        let next = runningEntry(id: 2, startedAt: at(1300))
        #expect(detector.tick(now: at(1300), idle: 0, running: next) == nil)
    }

    @Test func messageCountsWholeMinutes() {
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.locale = Locale(identifier: "en_US")
        format.timeZone = TimeZone(identifier: "America/Chicago")!
        let since = ISO8601DateFormatter().date(from: "2026-10-12T19:15:00Z")!

        let ninety = AwayPrompt(entryID: 1, awaySince: since, returnedAt: since + 90)
        #expect(ninety.message(timeFormat: format) == "You were away for 1 minute (since 2:15\u{202F}PM).")
        let long = AwayPrompt(entryID: 1, awaySince: since, returnedAt: since + 23 * 60 + 59)
        #expect(long.message(timeFormat: format) == "You were away for 23 minutes (since 2:15\u{202F}PM).")
    }
}

@Suite struct AwayDropTests {
    private func setUp() throws -> (PunchcardCore.Database, TimerEngine, Entry) {
        let db = try PunchcardCore.Database.inMemory()
        let engine = TimerEngine(database: db, now: { start + 7200 })
        let client = try #require(ClientRepository(database: db).all().first?.id)
        let entry = try engine.start(clientID: client, at: start)
        return (db, engine, entry)
    }

    @Test func dropContinueEndsAtAwaySinceAndStartsAgainAtReturn() throws {
        let (db, engine, entry) = try setUp()
        let id = try #require(entry.id)
        let prompt = AwayPrompt(entryID: id, awaySince: at(1800), returnedAt: at(3600))

        let next = try #require(try engine.dropContinue(prompt))

        #expect(try EntryRepository(database: db).find(id: id)?.endedAt == at(1800))
        #expect(next.isRunning)
        #expect(next.clientID == entry.clientID)
        #expect(next.startedAt == at(3600))
        #expect(try engine.running() == next)
    }

    @Test func dropStopEndsOnly() throws {
        let (db, engine, entry) = try setUp()
        let id = try #require(entry.id)
        let prompt = AwayPrompt(entryID: id, awaySince: at(1800), returnedAt: at(3600))

        let ended = try engine.dropStop(prompt)

        #expect(ended?.endedAt == at(1800))
        #expect(try engine.running() == nil)
        #expect(try EntryRepository(database: db).entries(overlapping: start, at(86400)).count == 1)
    }

    @Test(arguments: [true, false])
    func dropOnAStoppedEntryClampsAndCreatesNothing(continuing: Bool) throws {
        let (db, engine, entry) = try setUp()
        let id = try #require(entry.id)
        let prompt = AwayPrompt(entryID: id, awaySince: at(1800), returnedAt: at(3600))
        let repository = EntryRepository(database: db)

        // Stopped after the away period began: the drop pulls the end back to awaySince.
        try engine.stop(at: at(2400))
        _ = continuing ? try engine.dropContinue(prompt) : try engine.dropStop(prompt)
        #expect(try repository.find(id: id)?.endedAt == at(1800))

        // Stopped before awaySince: the earlier end stays.
        try repository.update(try #require(try repository.find(id: id)).with(endedAt: at(1200)))
        _ = continuing ? try engine.dropContinue(prompt) : try engine.dropStop(prompt)
        #expect(try repository.find(id: id)?.endedAt == at(1200))

        #expect(try engine.running() == nil)
        #expect(try repository.entries(overlapping: start, at(86400)).count == 1)
    }

    @Test func dropContinueAfterSwitchingClientsClampsOnly() throws {
        let (db, engine, entry) = try setUp()
        let id = try #require(entry.id)
        let other = try #require(try ClientRepository(database: db).insert(name: "Acme").id)
        let switched = try engine.start(clientID: other, at: at(2400))
        let prompt = AwayPrompt(entryID: id, awaySince: at(1800), returnedAt: at(2000))

        #expect(try engine.dropContinue(prompt) == nil)
        #expect(try EntryRepository(database: db).find(id: id)?.endedAt == at(1800))
        #expect(try engine.running() == switched)
    }
}

private extension Entry {
    func with(endedAt: Date) -> Entry {
        var entry = self
        entry.endedAt = endedAt
        return entry
    }
}
