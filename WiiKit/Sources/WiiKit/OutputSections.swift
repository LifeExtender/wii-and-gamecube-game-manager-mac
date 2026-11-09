import Foundation

/// One `[name]` block of the tools' `--sections` output.
public struct OutputSection: Sendable {
    public let name: String
    public let values: [String: String]
}

public func parseSections(_ text: String) -> [OutputSection] {
    var result: [OutputSection] = []
    var name: String?
    var values: [String: String] = [:]

    func flush() {
        if let name { result.append(OutputSection(name: name, values: values)) }
        values = [:]
    }

    for rawLine in text.split(whereSeparator: \.isNewline) {
        let line = String(rawLine)
        if line.hasPrefix("["), line.hasSuffix("]") {
            flush()
            name = String(line.dropFirst().dropLast())
        } else if name != nil, let equals = line.firstIndex(of: "=") {
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
    }
    flush()
    return result
}
