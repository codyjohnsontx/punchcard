/// Formats tracked seconds. Hours are not zero padded and may exceed 99 (`160:25`);
/// partial minutes and seconds are truncated, never rounded up.
public enum DurationFormatter {
    /// `h:mm`, used everywhere except the running clock.
    public static func hoursMinutes(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        return "\(seconds / 3600):\(twoDigits(seconds / 60 % 60))"
    }

    /// `h:mm:ss`, for the running clock in the dropdown.
    public static func hoursMinutesSeconds(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        return "\(hoursMinutes(seconds)):\(twoDigits(seconds % 60))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
