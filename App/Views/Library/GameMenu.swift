import SwiftUI
import WiiKit

/// The same commands wherever a game can be acted on.
struct GameMenu: View {
    @Environment(AppModel.self) private var model
    let games: [Game]
    let list: GameList

    var body: some View {
        if let first = games.first {
            let onDrive = first.isOnPartition
            Button(onDrive ? "Extract…" : "Convert…") {
                model.activeSheet = .convert(ConvertDraft(games: games, format: onDrive ? .iso : .wbfs))
            }
            SendToMenu(games: games, list: list)
            if !onDrive {
                let wbfs = games.filter { $0.container == "WBFS" }
                if !wbfs.isEmpty { Button("Resplit…") { model.activeSheet = .resplit(wbfs) } }
                Divider()
                Button("Copy To…") { model.activeSheet = .transfer(TransferDraft(games: games, move: false)) }
                Button("Move To…") { model.activeSheet = .transfer(TransferDraft(games: games, move: true)) }
            }
            Divider()
            if games.contains(where: { $0.platform == "Wii" }) {
                Button("Verify") { model.enqueueVerify(games) }
            }
            if games.count == 1 {
                Button("Browse Files") {
                    list.selection = [first.id]
                    model.detailTab = .files
                    model.detailVisible = true
                }
                if !onDrive { Button("Show in Finder") { model.reveal(first) } }
            }
            Divider()
            Button("Download Artwork") { model.downloadCovers(gameIDs: games.map(\.gameID), kinds: CoverKind.allCases) }
            if games.count == 1 {
                Button("Set Custom Title…") { model.activeSheet = .customTitle(first) }
            }
            Button("Export to CSV…") { model.exportGames(from: list, ids: Set(games.map(\.id))) }
            Divider()
            Button(onDrive ? "Delete from Drive…" : "Move to Trash…", role: .destructive) { model.confirmDelete(games) }
        }
    }
}

struct SendToMenu: View {
    @Environment(AppModel.self) private var model
    let games: [Game]
    let list: GameList

    var body: some View {
        let destinations = model.destinations(excluding: list)
        if !destinations.isEmpty {
            Menu("Send To") {
                ForEach(destinations) { destination in
                    Button(destination.name) { model.send(games, to: destination) }
                }
            }
        }
    }
}
