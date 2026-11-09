import Foundation

public enum GameLocation: Hashable, Sendable {
    case file(URL)
    case partition(device: String, slot: Int)
}

public struct Game: Identifiable, Hashable, Sendable {
    /// The exact source spec `wit` and `wwt` accept for this disc.
    public let id: String
    public let gameID: String
    public let discName: String
    public let region: String
    public let fileType: String
    public let sizeBytes: Int64
    public let bytesOnDisk: Int64
    public let location: GameLocation
    public var discNumber = 0

    public init(
        id: String, gameID: String, discName: String, region: String, fileType: String,
        sizeBytes: Int64, bytesOnDisk: Int64, location: GameLocation
    ) {
        self.id = id
        self.gameID = gameID
        self.discName = discName
        self.region = region
        self.fileType = fileType
        self.sizeBytes = sizeBytes
        self.bytesOnDisk = bytesOnDisk
        self.location = location
    }

    public var isOnPartition: Bool {
        if case .partition = location { return true }
        return false
    }

    public var fileURL: URL? {
        if case .file(let url) = location { return url }
        return nil
    }

    public var directory: String {
        switch location {
        case .file(let url): return url.deletingLastPathComponent().path
        case .partition(let device, _): return device
        }
    }

    public var filename: String {
        switch location {
        case .file(let url): return url.lastPathComponent
        case .partition(_, let slot): return "Slot \(slot)"
        }
    }

    public var container: String {
        fileType.split(separator: "/").first.map(String.init) ?? fileType
    }

    public var platform: String {
        fileType.uppercased().hasSuffix("/GC") ? "GameCube" : "Wii"
    }

    /// Distinguishes the discs of a multi-disc game, which share a game ID.
    public var identity: String { "\(gameID)-\(discNumber)" }

    /// Keys a remembered disc number to this exact file, so a replaced file is read again.
    public var discCacheKey: String { "\(id)|\(bytesOnDisk)" }
}

public enum OutputFormat: String, CaseIterable, Sendable, Identifiable, Codable {
    case wbfs, iso
    public var id: String { rawValue }
    public var fileExtension: String { rawValue }
    public var flag: String { "--\(rawValue)" }
}

public enum SplitMode: String, CaseIterable, Sendable, Identifiable, Codable {
    case none, twoGB, fourGB
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "No split"
        case .twoGB: return "2 GB - 32 KB"
        case .fourGB: return "4 GB - 32 KB"
        }
    }
    public var arguments: [String] {
        switch self {
        case .none: return []
        case .twoGB: return ["--split", "--split-size", "2g-32k"]
        case .fourGB: return ["--split", "--split-size", "4g-32k"]
        }
    }
}

public enum CopyMode: String, CaseIterable, Sendable, Identifiable, Codable {
    case gamePartition, allPartitions, exact
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .gamePartition: return "Game partition only"
        case .allPartitions: return "All partitions"
        case .exact: return "1:1 copy"
        }
    }
    public var arguments: [String] {
        switch self {
        case .gamePartition: return ["--psel", "data"]
        case .allPartitions: return ["--psel", "all"]
        case .exact: return ["--raw"]
        }
    }
}

public enum NamingStyle: String, CaseIterable, Sendable, Identifiable, Codable {
    case gameID, gameIDTitle
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .gameID: return "GAMEID.ext"
        case .gameIDTitle: return "GAMEID_Title.ext"
        }
    }
}

public struct PartitionSpace: Equatable, Sendable {
    public let usedMiB: Int64
    public let freeMiB: Int64
    public let totalMiB: Int64
    public let usedDiscs: Int
    public let totalDiscs: Int
}

public struct PartitionContents: Sendable {
    public let games: [Game]
    public let space: PartitionSpace?

    public init(games: [Game], space: PartitionSpace?) {
        self.games = games
        self.space = space
    }
}
