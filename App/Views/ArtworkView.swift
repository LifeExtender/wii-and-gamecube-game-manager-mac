import SwiftUI
import WiiKit

struct ArtworkView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<String> = []

    var body: some View {
        let rows = model.missingArtworkRows()
        let _ = model.artworkRevision
        Group {
            if rows.isEmpty {
                ContentUnavailableView(
                    "All Artwork Saved", systemImage: "checkmark.circle",
                    description: Text("Every game in your libraries has all four images."))
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Title", value: \.title)
                    TableColumn("Game ID") { Text($0.gameID).monospaced().foregroundStyle(.secondary) }.width(min: 70, ideal: 84)
                    TableColumn("Cover") { mark($0.flat) }.width(52)
                    TableColumn("3D") { mark($0.threeD) }.width(52)
                    TableColumn("Disc") { mark($0.disc) }.width(52)
                    TableColumn("Full") { mark($0.full) }.width(52)
                }
                .alternatingRowBackgrounds(.disabled)
            }
        }
        .navigationTitle("Artwork")
        .navigationSubtitle(rows.isEmpty ? "" : "\(rows.count) incomplete")
        .toolbar {
            ToolbarItem {
                Menu("Download") {
                    let targets = selection.isEmpty ? rows.map(\.gameID) : Array(selection)
                    Button("All Types") { model.downloadCovers(gameIDs: targets, kinds: CoverKind.allCases) }
                    Divider()
                    ForEach(CoverKind.allCases) { kind in
                        Button("\(kind.label) Only") { model.downloadCovers(gameIDs: targets, kinds: [kind]) }
                    }
                }
                .disabled(rows.isEmpty)
            }
            ToolbarItem {
                Menu {
                    Button("Export to CSV…") { model.exportMissingArtwork(rows) }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .disabled(rows.isEmpty)
            }
        }
    }

    private func mark(_ present: Bool) -> some View {
        Circle()
            .fill(present ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.hairline))
            .frame(width: 8, height: 8)
    }
}
