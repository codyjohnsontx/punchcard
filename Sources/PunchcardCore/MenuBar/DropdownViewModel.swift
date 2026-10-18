import Foundation

/// The dropdown's contents, derived from a `TrackerSnapshot`. Pure data: the view decides
/// layout, this decides what is shown.
///
/// Single-client mode (at most one active client): a headline, one Start/Stop button and one
/// totals row. Multi-client mode: a row per active client with its own Start or Stop, then a
/// totals row per client with time and an "All" row.
public struct DropdownViewModel: Equatable, Sendable {
    public struct ClientRow: Equatable, Identifiable, Sendable {
        public let id: Int64
        public let name: String
        public let isRunning: Bool
        /// The running clock as `h:mm:ss`, or nil while this client's clock is stopped.
        public let clock: String?
    }

    public struct TotalsRow: Equatable, Identifiable, Sendable {
        public static let allID = "all"
        public static let allName = "All"

        public let id: String
        public let name: String
        public let today: String
        public let week: String
        public let month: String
    }

    public let isRunning: Bool
    public let isSingleClient: Bool
    /// `● 1:42:07`, plus the client name in multi-client mode; nil when stopped.
    public let headline: String?
    /// The client the single Start button starts; nil when no client is active.
    public let singleClientID: Int64?
    /// One row per active client, plus the running client if it is archived. Empty in
    /// single-client mode.
    public let clientRows: [ClientRow]
    /// Single-client mode: one row with the overall totals. Multi-client mode: a row per client
    /// with time in any period (active ones first), then the "All" row.
    public let totalsRows: [TotalsRow]

    public init(_ snapshot: TrackerSnapshot) {
        isRunning = snapshot.running != nil
        isSingleClient = snapshot.isSingleClient
        singleClientID = snapshot.clients.first?.id

        let clock = DurationFormatter.hoursMinutesSeconds(snapshot.runningSeconds)
        headline = snapshot.running.map { _ in
            var text = "\(MenuBarLabel.runningMark) \(clock)"
            if !snapshot.isSingleClient, let name = snapshot.runningClientName {
                text += " \(name)"
            }
            return text
        }

        let periods = [snapshot.today, snapshot.thisWeek, snapshot.thisMonth]
        if snapshot.isSingleClient {
            clientRows = []
            totalsRows = [Self.totalsRow(id: TotalsRow.allID, name: TotalsRow.allName, periods.map(\.overall))]
        } else {
            var ids = snapshot.clients.compactMap(\.id)
            if let running = snapshot.running, !ids.contains(running.clientID) {
                ids.append(running.clientID)
            }
            clientRows = ids.map { id in
                let isRunning = snapshot.running?.clientID == id
                return ClientRow(id: id, name: snapshot.name(of: id), isRunning: isRunning, clock: isRunning ? clock : nil)
            }

            let others = Set(periods.flatMap { $0.byClient.keys }).subtracting(ids)
                .sorted { snapshot.name(of: $0).localizedStandardCompare(snapshot.name(of: $1)) == .orderedAscending }
            totalsRows = (ids + others).map { id in
                Self.totalsRow(id: "client-\(id)", name: snapshot.name(of: id), periods.map { $0.seconds(for: id) })
            } + [Self.totalsRow(id: TotalsRow.allID, name: TotalsRow.allName, periods.map(\.overall))]
        }
    }

    private static func totalsRow(id: String, name: String, _ seconds: [Int]) -> TotalsRow {
        TotalsRow(
            id: id, name: name,
            today: DurationFormatter.hoursMinutes(seconds[0]),
            week: DurationFormatter.hoursMinutes(seconds[1]),
            month: DurationFormatter.hoursMinutes(seconds[2]))
    }
}
