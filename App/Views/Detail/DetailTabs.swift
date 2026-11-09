import SwiftUI
import WiiKit

struct OverviewTab: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let about: GameInfo?

    var body: some View {
        if let about {
            VStack(alignment: .leading, spacing: 20) {
                if !about.synopsis.isEmpty { Synopsis(text: about.synopsis) }
                InfoGroup(title: "Details") {
                    row("Developer", about.developer)
                    row("Publisher", about.publisher)
                    row("Released", about.year)
                    row("Genre", about.genre.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).capitalized }.joined(separator: ", "))
                    row("Players", about.players.isEmpty ? "" : (about.players == "1" ? "1" : "Up to \(about.players)"))
                    row("Online", about.onlinePlayers.isEmpty ? "" : "Up to \(about.onlinePlayers)")
                    row("Rating", about.rating)
                    row("Languages", about.languages.replacingOccurrences(of: ",", with: ", "))
                }
                if !about.controls.isEmpty {
                    InfoGroup(title: "Controllers") {
                        FlowTags(tags: about.controls)
                            .padding(.top, 2)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Synopsis, players and controllers come from the game database.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Download Game Database") { model.updateDatabase() }
                    .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty { InfoRow(label, value) }
    }
}

/// Tags that wrap onto further lines as needed.
private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(tags, id: \.self) { Tag(text: $0) }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let rows = arrange(subviews, width: width)
        return CGSize(width: width, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            for (index, x) in row.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat
        var items: [(Int, CGFloat)]
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var current = Row(y: 0, height: 0, items: [])
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x + size.width > width, !current.items.isEmpty {
                rows.append(current)
                y += current.height + spacing
                x = 0
                current = Row(y: y, height: 0, items: [])
            }
            current.items.append((index, x))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

struct FilesTab: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var tree: [DiscFileNode] = []
    @State private var allFiles: [DiscFile] = []
    @State private var search = ""
    @State private var loading = true
    @State private var failure: String?

    private var matches: [DiscFile] {
        allFiles.filter { $0.path.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading files…").font(.callout).foregroundStyle(.secondary)
                }
            } else if let failure {
                Text(failure).font(.callout).foregroundStyle(.secondary)
            } else {
                QuietField(placeholder: "Filter \(allFiles.count) files", text: $search)
                if search.isEmpty {
                    OutlineGroup(tree, children: \.children) { node in
                        row(node.name, node.sizeBytes, folder: node.children != nil)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(matches.prefix(400), id: \.path) { row($0.path, $0.sizeBytes, folder: false) }
                    }
                    if matches.count > 400 {
                        Text("Showing the first 400 matches").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .task(id: game.id) {
            do {
                allFiles = try await model.engine.discFiles(source: game.id)
                tree = DiscFiles.tree(allFiles)
            } catch {
                failure = error.localizedDescription
            }
            loading = false
        }
    }

    private func row(_ name: String, _ size: Int64, folder: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: folder ? "folder" : "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(name).font(.callout).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text(byteText(size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

private struct Synopsis: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.callout)
                .lineSpacing(2.5)
                .lineLimit(expanded ? nil : 5)
                .textSelection(.enabled)
            Button(expanded ? "Less" : "More") {
                withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}
