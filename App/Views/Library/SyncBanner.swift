import SwiftUI
import WiiKit

/// Offers games from this computer that a connected drive doesn't have yet.
struct SyncBanner: View {
    @Environment(AppModel.self) private var model
    let prompt: SyncPrompt
    @State private var sizes: [String: Int64] = [:]

    private var bytes: Int64 { prompt.games.reduce(0) { $0 + (sizes[$1.id] ?? 0) } }
    private var hasSizes: Bool { prompt.games.allSatisfy { sizes[$0.id] != nil } }
    private var capacity: (free: Int64, total: Int64)? { model.capacity(of: prompt.drive) }

    /// Leaves a one percent margin, since these sizes are estimates.
    private var fits: Bool {
        guard let capacity, hasSizes else { return true }
        return Double(bytes) * 1.01 <= Double(capacity.free)
    }

    private var headline: String {
        prompt.games.count == 1
            ? "\(model.displayTitle(for: prompt.games[0])) isn't on \(prompt.drive.name)"
            : "\(prompt.games.count) games aren't on \(prompt.drive.name)"
    }

    private var names: String {
        let titles = prompt.games.prefix(2).map(model.displayTitle(for:))
        let others = prompt.games.count - titles.count
        if prompt.games.count == 1 { return "It's in your library but not on this drive" }
        return others > 0 ? "\(titles.joined(separator: ", ")) and \(others) more" : titles.joined(separator: " and ")
    }

    private var sizeText: String? {
        guard hasSizes else { return nil }
        if !fits, let capacity { return "about \(byteText(bytes)), but only \(byteText(capacity.free)) free" }
        return "about \(byteText(bytes))"
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: -12) {
                ForEach(Array(prompt.games.prefix(3).enumerated()), id: \.element.id) { index, game in
                    CoverTile(gameID: game.gameID, pixels: 120, corner: 3)
                        .frame(height: 44)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .zIndex(Double(3 - index))
                        .onAppear { model.requestArtwork(.flat, gameID: game.gameID) }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: headline)
                Text([sizeText, names].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(fits ? .secondary : Color.red)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Not Now") { model.decline(prompt.games, on: prompt.drive) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Button("Review…") {
                model.activeSheet = .addGames(prompt.drive, preselected: Set(prompt.games.map(\.id)))
            }
            .buttonStyle(.bordered)
            Button(prompt.games.count == 1 ? "Add" : "Add All") {
                model.enqueueLoaderCopies(prompt.games, to: prompt.drive)
            }
            .primaryAction()
            .disabled(!fits || !hasSizes)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.22)))
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .task(id: prompt.games.map(\.id)) { sizes = await model.estimatedSizes(of: prompt.games) }
    }
}
