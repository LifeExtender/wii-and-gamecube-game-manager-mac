import Foundation
import WiiKit

enum Pane: Hashable { case library(UUID), activity, artwork }

enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview", disc = "Disc", files = "Files"
    var id: String { rawValue }
}

/// One openable item in the sidebar's Drives section.
struct DriveEntry: Identifiable, Equatable {
    let identifier: String
    let diskIdentifier: String
    let name: String
    let sizeBytes: Int64
    let mountPoint: String?
    let freeBytes: Int64?
    var key = ""
    var id: String { identifier }
}

struct ConvertDraft: Identifiable {
    let id = UUID()
    let games: [Game]
    var format: OutputFormat
    var split: SplitMode = .fourGB
    var naming: NamingStyle = .gameID
    var subdirectories = true
    var destination: URL?
}

struct TransferDraft: Identifiable {
    let id = UUID()
    let games: [Game]
    let move: Bool
    var subdirectories = true
}

enum ActiveSheet: Identifiable {
    case convert(ConvertDraft)
    case transfer(TransferDraft)
    case resplit([Game])
    case format(preselected: String?)
    case customTitle(Game)
    case addGames(GameList, preselected: Set<String>)

    var id: String {
        switch self {
        case .convert(let draft): return "convert\(draft.id)"
        case .transfer(let draft): return "transfer\(draft.id)"
        case .resplit: return "resplit"
        case .format: return "format"
        case .customTitle(let game): return "title\(game.id)"
        case .addGames(let list, _): return "add\(list.id)"
        }
    }
}

struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Games on this computer that a connected drive doesn't have yet.
struct SyncPrompt: Identifiable {
    let drive: GameList
    let games: [Game]
    var id: UUID { drive.id }
}

enum Verification: Equatable {
    case running, passed, failed(String)
}

struct MissingArtRow: Identifiable {
    let gameID: String
    let title: String
    let flat: Bool
    let threeD: Bool
    let disc: Bool
    let full: Bool
    var id: String { gameID }
    var complete: Bool { flat && threeD && disc && full }
}
