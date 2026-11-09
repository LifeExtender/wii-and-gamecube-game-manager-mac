import Foundation

public enum ToolOutput {
    public static let interruptedExitCode: Int32 = 110

    /// Matches `wit` progress lines such as `53% copied in 0:01 (1315.1 MiB/sec) -> ETA 0:00`.
    public static func progressFraction(in line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3, trimmed.dropFirst(digits.count).first == "%",
            let percent = Double(digits), percent <= 100
        else { return nil }
        return percent / 100
    }

    private static let rateLine = try! NSRegularExpression(pattern: #"\(([0-9.]+ \S+)/sec\) -> ETA (\S+)"#)

    /// Reads the speed and time left from a `wit` progress line.
    public static func rateAndETA(in line: String) -> (rate: String, eta: String)? {
        guard let match = rateLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let rate = Range(match.range(at: 1), in: line), let eta = Range(match.range(at: 2), in: line)
        else { return nil }
        return ("\(line[rate])/s", String(line[eta]))
    }

    /// Reduces the tools' error output to the sentence worth showing.
    public static func failureDetail(stdout: String, stderr: String, exitCode: Int32) -> String {
        let lines = (stderr + "\n" + stdout).split(whereSeparator: \.isNewline).map(String.init)
        let messages = lines.filter { $0.hasPrefix("!!") && !$0.contains("ERROR #") }
            .map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
        if !messages.isEmpty { return messages.joined(separator: " ") }
        if let text = parseSections(stdout).compactMap({ $0.values["text"] }).first { return text }
        if let marker = lines.first(where: { $0.contains("ERROR #") }) { return marker }
        if let warning = lines.last(where: { $0.hasPrefix("!") }) {
            return warning.drop(while: { $0 == "!" || $0 == " " }).description
        }
        return "The tool stopped with exit code \(exitCode)."
    }
}
