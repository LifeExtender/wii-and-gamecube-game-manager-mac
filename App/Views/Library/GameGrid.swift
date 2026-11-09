import SwiftUI
import WiiKit

struct GameGrid: View {
    @Environment(AppModel.self) private var model
    @Bindable var list: GameList
    let rows: [GameRow]
    @FocusState private var focused: Bool
    /// Cards created after this moment are appearing through scrolling, and shouldn't animate in.
    @State private var entranceEnds = Date().addingTimeInterval(0.6)

    private var spacing: CGFloat { model.settings.coverSize < 140 ? 18 : 26 }
    private let margin: CGFloat = 26

    var body: some View {
        let onDrives = model.gameIDsOnDrives(excluding: list)
        GeometryReader { proxy in
            let columns = columnCount(for: proxy.size.width)
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns), spacing: 30) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            GameCard(
                                row: row, selected: list.selection.contains(row.id),
                                onDrive: onDrives.contains(row.gameID),
                                job: model.queue.activeJob(for: row.gameID),
                                justFinished: model.queue.recentlyFinished.contains(row.gameID),
                                entranceDelay: Date() < entranceEnds ? min(Double(index) * 0.016, 0.22) : nil
                            )
                            .transition(Motion.card)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focused = true
                                model.click(row.id, in: list, ordered: rows.map(\.id))
                            }
                            .contextMenu {
                                GameMenu(games: targets(for: row), list: list)
                            }
                        }
                    }
                    .animation(Motion.gentle, value: rows.map(\.id))
                    .padding(margin)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { list.selection = [] }
                }
                .defaultScrollAnchor(.top)
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) { move(-1, scroller) }
                .onKeyPress(.rightArrow) { move(1, scroller) }
                .onKeyPress(.upArrow) { move(-columns, scroller) }
                .onKeyPress(.downArrow) { move(columns, scroller) }
            }
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        max(1, Int((width - 2 * margin + spacing) / (model.settings.coverSize + spacing)))
    }

    /// A right-click on an unselected card acts on that card alone.
    private func targets(for row: GameRow) -> [Game] {
        list.selection.contains(row.id) ? model.selected(in: list) : [row.game]
    }

    private func move(_ delta: Int, _ scroller: ScrollViewProxy) -> KeyPress.Result {
        let ids = rows.map(\.id)
        guard !ids.isEmpty else { return .ignored }
        let current = list.selectionAnchor.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ids.count - 1) } ?? 0
        list.selection = [ids[next]]
        list.selectionAnchor = ids[next]
        withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(ids[next]) }
        return .handled
    }
}
