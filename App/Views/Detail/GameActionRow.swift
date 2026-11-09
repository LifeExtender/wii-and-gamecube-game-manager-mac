import SwiftUI
import WiiKit

/// Convert, Send To and the overflow menu, for one game or several.
struct GameActionRow: View {
    @Environment(AppModel.self) private var model
    let games: [Game]
    let list: GameList

    var body: some View {
        let onDrive = games.first?.isOnPartition == true
        let destinations = model.destinations(excluding: list)
        HStack(spacing: 8) {
            Button {
                model.activeSheet = .convert(ConvertDraft(games: games, format: onDrive ? .iso : .wbfs))
            } label: {
                Text(onDrive ? "Extract" : "Convert").frame(maxWidth: .infinity)
            }
            .tint(Theme.accent)
            if !destinations.isEmpty {
                Menu {
                    ForEach(destinations) { destination in
                        Button(destination.name) { model.send(games, to: destination) }
                    }
                } label: {
                    Text("Send To").frame(maxWidth: .infinity)
                }
                .menuIndicator(.hidden)
            }
            Menu {
                GameMenu(games: games, list: list)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
