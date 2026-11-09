import SwiftUI
import WiiKit

struct GameTable: View {
    @Environment(AppModel.self) private var model
    @Bindable var list: GameList
    let rows: [GameRow]
    @SceneStorage("gameTableColumns") private var columns = TableColumnCustomization<GameRow>()

    var body: some View {
        Table(rows, selection: $list.selection, sortOrder: $list.sortOrder, columnCustomization: $columns) {
            TableColumn("Title", value: \.title) { row in
                HStack(spacing: 10) {
                    CoverTile(gameID: row.gameID, pixels: 96, corner: 3).frame(width: 24)
                        .onAppear { model.requestArtwork(.flat, gameID: row.gameID) }
                    Text(row.title).lineLimit(1)
                }
            }
            .width(min: 220, ideal: 360)
            .customizationID("title")
            TableColumn("Game ID", value: \.gameID) { Text($0.gameID).monospaced().foregroundStyle(.secondary) }
                .width(min: 70, ideal: 84).customizationID("id")
            TableColumn("Region", value: \.region).width(min: 50, ideal: 60).customizationID("region")
            TableColumn("Format", value: \.format).width(min: 50, ideal: 64).customizationID("format")
            TableColumn("Platform", value: \.platform).width(min: 60, ideal: 76).customizationID("platform")
            TableColumn("Size", value: \.sizeBytes) { Text(byteText($0.sizeBytes)).monospacedDigit() }
                .width(min: 66, ideal: 80).customizationID("size")
            TableColumn("Filename", value: \.filename).width(min: 90, ideal: 170).customizationID("filename").defaultVisibility(.hidden)
            TableColumn("Directory", value: \.directory).width(min: 90, ideal: 240).customizationID("directory").defaultVisibility(.hidden)
            TableColumn("Notes", value: \.notes).width(min: 70, ideal: 130).customizationID("notes").defaultVisibility(.hidden)
        }
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            GameMenu(games: model.games(ids: ids, in: list), list: list)
        }
    }
}
