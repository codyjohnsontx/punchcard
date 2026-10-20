/// Builds RFC 4180 text: fields joined by commas, records ended by LF, and a field quoted
/// (with its quotes doubled) when it holds a comma, a quote or a line break. Every document
/// starts with its header row, so an empty export is still a well-formed file.
public enum CSVWriter {
    public static func document(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map(record).joined()
    }

    /// One record, including its line ending.
    public static func record(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + "\n"
    }

    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
