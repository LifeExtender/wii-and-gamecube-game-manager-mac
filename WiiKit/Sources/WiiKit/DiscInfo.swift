import Foundation

public struct DiscSection: Identifiable, Sendable, Equatable {
    public var id: String { index }
    public let index: String
    public let kind: String
    public let sizeBytes: Int64
    public let status: String

    public init(index: String, kind: String, sizeBytes: Int64, status: String) {
        self.index = index
        self.kind = kind
        self.sizeBytes = sizeBytes
        self.status = status
    }

    public var label: String { kind.prefix(1).uppercased() + kind.dropFirst().lowercased() }
}

/// What the image itself reports, independent of the file format holding it.
public struct DiscInfo: Sendable, Equatable {
    public var discSize: Int64?
    public var usedSize: Int64?
    public var format: String?
    public var platform: String?
    public var discID: String?
    public var name: String?
    public var region: String?
    public var requiredSystem: String?
    public var partitionCount: Int?
    public var protection: String?
    public var directories: Int?
    public var files: Int?
    public var discNumber: Int?
    public var version: Int?
    public var partitions: [DiscSection] = []

    public init() {}

    public static func parse(dump: String) -> DiscInfo {
        var info = DiscInfo()
        for rawLine in dump.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let partition = parsePartitionRow(line) {
                info.partitions.append(partition)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch label {
            case "Virtual size", "ISO file size":
                info.discSize = decimalSize(value)
            case "Scrubbed size":
                info.usedSize = decimalSize(value)
            case "File & disc type":
                let pieces = value.components(separatedBy: "&").map { $0.trimmingCharacters(in: .whitespaces) }
                info.format = pieces.first
                if pieces.count > 1 { info.platform = pieces[1] }
            case "Disc & part IDs":
                info.discID = value.components(separatedBy: ",").compactMap { field -> String? in
                    let parts = field.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                    return parts.count == 2 && parts[0] == "disc" ? parts[1] : nil
                }.first
            case "Disc name":
                info.name = value
            case "ID Region":
                info.region = value.components(separatedBy: "[").first?.trimmingCharacters(in: .whitespaces)
            case "System version":
                info.requiredSystem = value.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces)
            case "Partitions":
                info.partitionCount = Int(value.prefix(while: \.isNumber))
                if let open = value.firstIndex(of: "["), let close = value.lastIndex(of: "]"), open < close {
                    let flags = value[value.index(after: open)..<close]
                    info.protection = flags.isEmpty ? nil : flags.prefix(1).uppercased() + flags.dropFirst()
                }
            case "Directories":
                info.directories = Int(value.prefix(while: \.isNumber))
            case "Files":
                info.files = Int(value.prefix(while: \.isNumber))
            default:
                break
            }
        }
        return info
    }

    /// `118240000/hex = 4699979776 = 4482 MiB` holds the byte count in its second field.
    static func decimalSize(_ value: String) -> Int64? {
        let fields = value.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 2 else { return nil }
        return Int64(fields[1].prefix(while: \.isNumber))
    }

    private static let partitionRow = try! NSRegularExpression(
        pattern: #"^(\d+\.\d+)\s+(\S+)(?:\s+\S+)?\s+[0-9a-fA-F]+\s+\.\.\s+[0-9a-fA-F]+\s+[0-9a-fA-F]+\s+=\s+(\d+)\s+=\s+\d+\s*(.*)$"#)

    /// Matches rows such as `0.0  DATA 0  f800000 .. 12370000  2b70000 = 45547520 = 43  enc,faked`.
    static func parsePartitionRow(_ line: String) -> DiscSection? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = partitionRow.firstMatch(in: line, range: range), match.numberOfRanges == 5,
            let index = Range(match.range(at: 1), in: line), let kind = Range(match.range(at: 2), in: line),
            let size = Range(match.range(at: 3), in: line), let status = Range(match.range(at: 4), in: line),
            let bytes = Int64(line[size])
        else { return nil }
        return DiscSection(index: String(line[index]), kind: String(line[kind]), sizeBytes: bytes, status: String(line[status]))
    }

    /// Reads `TSTE99 00.00`, the ID followed by disc number and version.
    mutating func applyID8(_ output: String) {
        guard let line = output.split(whereSeparator: \.isNewline).first else { return }
        let fields = line.split(separator: " ")
        guard fields.count >= 2 else { return }
        let numbers = fields[1].split(separator: ".")
        guard numbers.count == 2 else { return }
        discNumber = Int(numbers[0])
        version = Int(numbers[1])
    }
}
