import SwiftUI
import WiiKit

struct SelectionSummary: View {
    @Environment(AppModel.self) private var model
    let games: [Game]
    let list: GameList

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                ForEach(Array(games.prefix(3).enumerated().reversed()), id: \.element.id) { index, game in
                    CoverTile(gameID: game.gameID, pixels: 320)
                        .frame(height: 170)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .rotationEffect(.degrees(Double(index) * 5))
                        .offset(x: CGFloat(index) * 22)
                        .transition(Motion.card)
                }
            }
            .animation(Motion.gentle, value: games.prefix(3).map(\.id))
            .frame(height: 200)
            VStack(spacing: 3) {
                Text("\(games.count) games selected").font(.title3.weight(.semibold))
                Text(byteText(games.reduce(0) { $0 + $1.bytesOnDisk })).font(.callout).foregroundStyle(.secondary)
            }
            GameActionRow(games: games, list: list)
            Spacer()
        }
        .padding(20)
    }
}

struct LibrarySummary: View {
    @Environment(AppModel.self) private var model
    let list: GameList

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    if let first = list.games.first {
                        HStack(spacing: -22) {
                            ForEach(Array(list.games.prefix(4).enumerated()), id: \.element.id) { index, game in
                                CoverTile(gameID: game.gameID, pixels: 240)
                                    .frame(height: 112)
                                    .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                                    .zIndex(Double(4 - index))
                                    .id(first.id + game.id)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    Text(list.name).font(.title3.weight(.semibold)).lineLimit(2)
                    Text(list.games.count == 1 ? "1 game" : "\(list.games.count) games")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let space = list.space, space.totalMiB > 0 {
                    InfoGroup(title: "Drive") {
                        VStack(alignment: .leading, spacing: 6) {
                            UsageBar(fraction: Double(space.usedMiB) / Double(space.totalMiB))
                            Text("\(byteText(space.freeMiB * 1_048_576)) free of \(byteText(space.totalMiB * 1_048_576))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        InfoRow("Slots used", "\(space.usedDiscs) of \(space.totalDiscs)")
                    }
                } else if list.totalBytes > 0 {
                    InfoGroup(title: "Storage") { InfoRow("Total", byteText(list.totalBytes)) }
                }
                breakdown("Platforms", list.games.map(\.platform))
                breakdown("Formats", list.games.map(\.container))
                breakdown("Regions", list.games.map(\.region))
                comparison
                if !list.games.isEmpty {
                    Button("Export to CSV…") { model.exportGames(from: list, ids: nil) }
                        .buttonStyle(.link)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func breakdown(_ title: String, _ values: [String]) -> some View {
        let counts = Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        if !counts.isEmpty {
            InfoGroup(title: title) {
                ForEach(counts.sorted { $0.value > $1.value }, id: \.key) { key, count in
                    InfoRow(key, "\(count)")
                }
            }
        }
    }

    @ViewBuilder
    private var comparison: some View {
        let others = model.libraries.filter { $0 !== list && !$0.games.isEmpty }
        if !others.isEmpty && !list.games.isEmpty {
            InfoGroup(title: "Select games missing from") {
                ForEach(others) { other in
                    InfoRow(label: other.name) {
                        Button("Select") { model.selectMissing(from: other, in: list) }
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }
}
