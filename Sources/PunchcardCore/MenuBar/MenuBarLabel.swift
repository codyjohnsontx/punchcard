/// What the status item shows, from the `menu_bar_style` setting and the running clock.
///
/// Time style (the default): the icon alone when stopped; `● 1:42` when running, or
/// `● 1:42 Acme` when more than one client is active. Icon style: `clock` when stopped,
/// `clock.fill` when running.
public enum MenuBarLabel: Equatable, Sendable {
    public static let stoppedSymbol = "clock"
    public static let runningSymbol = "clock.fill"
    /// The running indicator in front of the time.
    public static let runningMark = "●"

    /// An SF Symbol and nothing else.
    case icon(systemName: String)
    /// Text in place of the icon.
    case text(String)

    public init(_ snapshot: TrackerSnapshot) {
        switch (snapshot.menuBarStyle, snapshot.running) {
        case (_, nil):
            self = .icon(systemName: Self.stoppedSymbol)
        case (.icon, .some):
            self = .icon(systemName: Self.runningSymbol)
        case (.time, .some):
            var text = "\(Self.runningMark) \(DurationFormatter.hoursMinutes(snapshot.runningSeconds))"
            if !snapshot.isSingleClient, let name = snapshot.runningClientName {
                text += " \(name)"
            }
            self = .text(text)
        }
    }
}
