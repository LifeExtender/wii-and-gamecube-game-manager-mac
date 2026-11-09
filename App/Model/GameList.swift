import Foundation
import Observation
import WiiKit

enum ListSource: Equatable {
    case folder(URL)
    case files([URL])
    case partition(device: String, identifier: String)

    var device: String? {
        if case .partition(let device, _) = self { return device }
        return nil
    }

    var folder: URL? {
        if case .folder(let url) = self { return url }
        return nil
    }
}

/// One library or drive shown in the sidebar, with its view state.
@MainActor @Observable
final class GameList: Identifiable {
    let id = UUID()
    let source: ListSource
    let name: String
    let driveIdentifier: String?
    /// Survives the disk being renumbered, so per-drive choices can be remembered.
    var syncKey: String?
    var hasLoaded = false
    var games: [Game] = []
    var selection: Set<String> = []
    var selectionAnchor: String?
    var search = ""
    var platformFilter: String?
    var regionFilter: String?
    var sortOrder = [KeyPathComparator(\GameRow.title)]
    var space: PartitionSpace?
    var isLoading = false
    var message: String?
    /// Lets a slow scan notice that a newer one has started, and discard its result.
    @ObservationIgnored var loadGeneration = 0

    init(source: ListSource, name: String, driveIdentifier: String? = nil) {
        self.source = source
        self.name = name
        self.driveIdentifier = driveIdentifier
    }

    var totalBytes: Int64 { games.reduce(0) { $0 + $1.bytesOnDisk } }
    var isDrive: Bool { driveIdentifier != nil }
}

struct GameRow: Identifiable {
    let game: Game
    let title: String
    let notes: String
    var id: String { game.id }
    var gameID: String { game.gameID }
    var sizeBytes: Int64 { game.bytesOnDisk }
    var format: String { game.container }
    var platform: String { game.platform }
    var region: String { game.region }
    var directory: String { game.directory }
    var filename: String { game.filename }
}
