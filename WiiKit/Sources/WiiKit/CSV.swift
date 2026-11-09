import Foundation

public enum CSV {
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func field(_ value: String) -> String {
        guard value.contains(where: { ",\"\r\n".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
