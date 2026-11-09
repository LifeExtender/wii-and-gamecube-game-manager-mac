import SwiftUI
import WiiKit

struct LibraryHeader: View {
    @Environment(AppModel.self) private var model
    @Bindable var list: GameList

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(list.name)
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 16)
                if list.isDrive { driveActions }
            }
            if list.isDrive, let capacity = model.capacity(of: list), capacity.total > 0 {
                CapacityLine(free: capacity.free, total: capacity.total)
            }
            filters
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var summary: String {
        let count = list.games.count
        var parts = ["\(count) \(count == 1 ? "game" : "games")"]
        if !list.isDrive, list.totalBytes > 0 { parts.append(byteText(list.totalBytes)) }
        return parts.joined(separator: " · ")
    }

    private var driveActions: some View {
        HStack(spacing: 8) {
            Button("Add Games…") { model.activeSheet = .addGames(list, preselected: []) }
                .primaryAction()
            Menu {
                if let identifier = list.driveIdentifier, let drive = model.drives.first(where: { $0.id == identifier }) {
                    Button("Format…") { model.activeSheet = .format(preselected: drive.diskIdentifier) }
                    Button("Eject") { model.eject(drive) }
                }
                Button("Reload") { model.reload(list) }
                if model.hasDeclined(on: list) {
                    Divider()
                    Button("Suggest Dismissed Games Again") { model.resetDeclined(on: list) }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var filters: some View {
        let platforms = tally(list.games.map(\.platform))
        let regions = tally(list.games.map(\.region))
        if platforms.count > 1 || regions.count > 1 {
            HStack(spacing: 4) {
                FilterChip(title: "All", count: nil, selected: list.platformFilter == nil && list.regionFilter == nil) {
                    list.platformFilter = nil
                    list.regionFilter = nil
                }
                if platforms.count > 1 {
                    ForEach(platforms, id: \.0) { name, count in
                        FilterChip(title: name, count: count, selected: list.platformFilter == name) {
                            list.platformFilter = list.platformFilter == name ? nil : name
                        }
                    }
                }
                if platforms.count > 1 && regions.count > 1 {
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 16).padding(.horizontal, 6)
                }
                if regions.count > 1 {
                    ForEach(regions, id: \.0) { name, count in
                        FilterChip(title: name, count: count, selected: list.regionFilter == name) {
                            list.regionFilter = list.regionFilter == name ? nil : name
                        }
                    }
                }
            }
        }
    }

    private func tally(_ values: [String]) -> [(String, Int)] {
        Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }
}

private struct CapacityLine: View {
    let free: Int64
    let total: Int64

    var body: some View {
        HStack(spacing: 12) {
            UsageBar(fraction: 1 - Double(free) / Double(total))
                .frame(maxWidth: 320)
            Text("\(byteText(free)) free of \(byteText(total))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LibraryFooter: View {
    @Environment(AppModel.self) private var model
    let list: GameList
    let rows: [GameRow]

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(Motion.snappy, value: status)
            Spacer()
            if model.settings.layout == .grid {
                Image(systemName: "square.grid.3x3").font(.caption2).foregroundStyle(.tertiary)
                Slider(value: $model.settings.coverSize, in: 110...260)
                    .controlSize(.mini)
                    .tint(.secondary)
                    .frame(width: 110)
                Image(systemName: "square.grid.2x2").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var status: String {
        let selected = model.selected(in: list)
        if !selected.isEmpty {
            return "\(selected.count) selected · \(byteText(selected.reduce(0) { $0 + $1.bytesOnDisk }))"
        }
        return rows.count == list.games.count ? "\(rows.count) shown" : "\(rows.count) of \(list.games.count) shown"
    }
}

struct EmptyDriveView: View {
    @Environment(AppModel.self) private var model
    let list: GameList

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive")
                .font(.system(size: 46, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            VStack(spacing: 5) {
                Text("This drive has no games yet").font(.title3.weight(.medium))
                Text("Choose from your libraries, and each game goes where USB loaders expect it.")
                    .foregroundStyle(.secondary)
            }
            Button("Add Games…") { model.activeSheet = .addGames(list, preselected: []) }
                .controlSize(.large)
                .primaryAction()
        }
    }
}
