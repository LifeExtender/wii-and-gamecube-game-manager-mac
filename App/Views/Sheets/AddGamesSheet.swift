import SwiftUI
import WiiKit

/// Picks games from every library for one drive, showing the space they will take.
struct AddGamesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let drive: GameList
    var preselected: Set<String> = []
    @State private var candidates: [Game] = []
    @State private var sizes: [String: Int64] = [:]
    @State private var selection: Set<String> = []
    @State private var search = ""

    private var capacity: (free: Int64, total: Int64)? { model.capacity(of: drive) }
    private var selectedBytes: Int64 { selection.reduce(0) { $0 + (sizes[$1] ?? 0) } }

    /// Leaves a one percent margin, since these sizes are estimates.
    private var fits: Bool {
        guard let capacity else { return true }
        return Double(selectedBytes) * 1.01 <= Double(capacity.free)
    }

    private var visible: [Game] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? candidates : candidates.filter {
            model.displayTitle(for: $0).localizedCaseInsensitiveContains(query) || $0.gameID.localizedCaseInsensitiveContains(query)
        }
        return matching.sorted { model.displayTitle(for: $0).localizedCaseInsensitiveCompare(model.displayTitle(for: $1)) == .orderedAscending }
    }

    private var capacityText: String {
        guard let capacity else { return "Choose the games to copy" }
        return "\(byteText(capacity.free)) free of \(byteText(capacity.total))"
    }

    var body: some View {
        SheetScaffold(title: "Add Games to \(drive.name)", subtitle: capacityText, width: 780) {
            VStack(alignment: .leading, spacing: 12) {
                if let capacity, capacity.total > 0 {
                    let total = Double(capacity.total)
                    ProjectedUsageBar(
                        used: Double(capacity.total - capacity.free) / total,
                        adding: Double(selectedBytes) / total,
                        overflow: !fits)
                }
                if candidates.isEmpty {
                    emptyState
                } else {
                    HStack(spacing: 8) {
                        QuietField(placeholder: "Search \(candidates.count) games", text: $search)
                        Button("Select All") { selection.formUnion(visible.map(\.id)) }
                        Button("Clear") { selection = [] }.disabled(selection.isEmpty)
                    }
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 16, alignment: .top)], spacing: 18) {
                            ForEach(visible) { game in
                                PickCard(game: game, size: sizes[game.id], selected: selection.contains(game.id)) {
                                    if selection.contains(game.id) { selection.remove(game.id) } else { selection.insert(game.id) }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 400)
                    .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if drive.source.device != nil {
                    Text("GameCube games aren't listed, because they can't run from a WBFS drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            Group {
                if selection.isEmpty {
                    Text("Wii games go to /wbfs and GameCube games to /games.")
                } else if fits {
                    Text("\(selection.count) selected · about \(byteText(selectedBytes))")
                } else {
                    Text("That is more than this drive has free.").foregroundStyle(.red)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(selection.count > 1 ? "Add \(selection.count) Games" : "Add Game") {
                model.enqueueLoaderCopies(candidates.filter { selection.contains($0.id) }, to: drive)
                // Anything unticked from a suggestion was a deliberate choice, so don't ask again.
                model.decline(candidates.filter { preselected.contains($0.id) && !selection.contains($0.id) }, on: drive)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .primaryAction()
            .disabled(selection.isEmpty || !fits)
        }
        .task {
            candidates = model.addableGames(to: drive)
            selection = preselected.intersection(candidates.map(\.id))
            sizes = await model.estimatedSizes(of: candidates)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text(model.libraries.contains { !$0.isDrive } ? "Everything in your libraries is already on this drive." : "Add a library first, then come back here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

private struct PickCard: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let size: Int64?
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                CoverTile(gameID: game.gameID, pixels: 280, corner: 5)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.9), selected ? Theme.accent : Color.black.opacity(0.28))
                            .shadow(color: .black.opacity(0.3), radius: 2)
                            .padding(5)
                            .opacity(selected || hovered ? 1 : 0)
                    }
                    .overlay {
                        if selected {
                            SelectionRing(corner: 7, inset: 3)
                        }
                    }
                    .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                    .scaleEffect(hovered && !Motion.reduced ? 1.03 : 1)
                    .animation(Motion.pop, value: selected)
                    .animation(Motion.reduced ? nil : .easeOut(duration: 0.14), value: hovered)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayTitle(for: game)).font(.caption.weight(.medium)).lineLimit(1)
                    Text(size.map(byteText) ?? game.platform).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .onAppear { model.requestArtwork(.flat, gameID: game.gameID) }
    }
}
