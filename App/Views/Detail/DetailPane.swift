import SwiftUI
import WiiKit

struct DetailPane: View {
    @Environment(AppModel.self) private var model
    let list: GameList

    var body: some View {
        let games = model.selected(in: list)
        Group {
            switch games.count {
            case 0: LibrarySummary(list: list).transition(.opacity)
            case 1: GameDetail(game: games[0], list: list).id(games[0].id).transition(.opacity)
            default: SelectionSummary(games: games, list: list).transition(.opacity)
            }
        }
        .animation(Motion.fade, value: games.count == 1 ? games[0].id : "\(min(games.count, 2))")
    }
}
