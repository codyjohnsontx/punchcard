import Foundation

/// Finds entries that share at least one instant with another entry. Two entries that only
/// touch (one ends exactly when the next starts, as a client switch produces) do not overlap.
/// A running entry extends to `now`.
public enum EntryOverlaps {
    /// Two overlapping entry IDs, the lower ID first.
    public struct Pair: Hashable, Sendable {
        public let first: Int64
        public let second: Int64

        public init(_ a: Int64, _ b: Int64) {
            first = min(a, b)
            second = max(a, b)
        }
    }

    /// Every overlapping pair among `entries`, in order of the earlier entry's start.
    /// Entries without an ID (not yet stored) are ignored.
    public static func pairs(in entries: [Entry], now: Date) -> [Pair] {
        let sorted = entries.filter { $0.id != nil }.sorted { ($0.startedAt, $0.id!) < ($1.startedAt, $1.id!) }
        var pairs: [Pair] = []
        for (index, entry) in sorted.enumerated() {
            let end = entry.endedAt ?? now
            for later in sorted[(index + 1)...] {
                guard later.startedAt < end else { break }
                if overlap(entry, later, now: now) {
                    pairs.append(Pair(entry.id!, later.id!))
                }
            }
        }
        return pairs
    }

    /// The IDs of every entry in `entries` that overlaps another one.
    public static func ids(in entries: [Entry], now: Date) -> Set<Int64> {
        Set(pairs(in: entries, now: now).flatMap { [$0.first, $0.second] })
    }

    /// Whether `[start, end)` shares an instant with `entry`; `end` nil means running. A
    /// zero-length entry holds no instant, so it overlaps nothing.
    public static func overlap(start: Date, end: Date?, _ entry: Entry, now: Date) -> Bool {
        max(start, entry.startedAt) < min(end ?? now, entry.endedAt ?? now)
    }

    public static func overlap(_ a: Entry, _ b: Entry, now: Date) -> Bool {
        overlap(start: a.startedAt, end: a.endedAt, b, now: now)
    }
}
