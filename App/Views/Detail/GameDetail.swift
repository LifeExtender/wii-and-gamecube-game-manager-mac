import SwiftUI
import WiiKit

struct GameDetail: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let list: GameList
    @State private var disc: DiscInfo?
    @State private var readFailure: String?

    private var about: GameInfo? { model.info[game.gameID] }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            ZStack(alignment: .top) {
                AmbientBackdrop(gameID: game.gameID)
                VStack(alignment: .leading, spacing: 18) {
                    CoverHero(gameID: game.gameID)
                        .frame(maxWidth: .infinity)
                    heading
                    GameActionRow(games: [game], list: list)
                    PillTabs(options: DetailTab.allCases, label: \.rawValue, selection: $model.detailTab)
                    Group {
                        switch model.detailTab {
                        case .overview: OverviewTab(game: game, about: about)
                        case .disc: discTab
                        case .files: FilesTab(game: game)
                        }
                    }
                    .id(model.detailTab)
                    .transition(Motion.content)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .task(id: game.id) {
            do {
                disc = try await model.discInfo(for: game)
            } catch {
                readFailure = "This image could not be read: \(error.localizedDescription)"
            }
        }
    }

    private var heading: some View {
        VStack(spacing: 8) {
            VStack(spacing: 3) {
                Text(model.displayTitle(for: game))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let line = byline {
                    Text(line).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            HStack(spacing: 5) {
                Tag(text: game.platform)
                if !game.region.isEmpty { Tag(text: game.region) }
                Tag(text: game.container)
                Tag(text: byteText(game.bytesOnDisk))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var byline: String? {
        guard let about else { return nil }
        let genre = about.genre.split(separator: ",").first.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let parts = [about.publisher.isEmpty ? nil : about.publisher, about.year.isEmpty ? nil : about.year, genre]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    @ViewBuilder
    private var discTab: some View {
        if let readFailure {
            Text(readFailure).font(.callout).foregroundStyle(.secondary)
        } else if let disc {
            VStack(alignment: .leading, spacing: 20) {
                identity(disc)
                storage(disc)
                partitions(disc)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading disc…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func identity(_ disc: DiscInfo) -> some View {
        InfoGroup(title: "Identity") {
            InfoRow(label: "Game ID") { Text(game.gameID).monospaced().textSelection(.enabled) }
            if let name = disc.name, name != model.displayTitle(for: game) {
                InfoRow("Title on disc", name)
            }
            InfoRow("Platform", disc.platform ?? game.platform)
            if let region = disc.region { InfoRow("Region", region) }
            if let number = disc.discNumber, number > 0 { InfoRow("Disc", "\(number + 1)") }
            if let version = disc.version { InfoRow("Revision", "\(version)") }
            if let system = disc.requiredSystem { InfoRow("Requires", system) }
            if disc.platform == "Wii", let protection = disc.protection { InfoRow("Protection", protection) }
            if disc.platform == "Wii" { verificationRow }
        }
    }

    private var verificationRow: some View {
        InfoRow(label: "Integrity") {
            switch model.verification[game.id] {
            case .running:
                ProgressView().controlSize(.mini)
            case .passed:
                Label("Passed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.primary)
            case .failed(let detail):
                Text("Damaged").foregroundStyle(.red).help(detail)
            case nil:
                Button("Verify") { model.enqueueVerify([game]) }
                    .buttonStyle(.link)
            }
        }
    }

    private func storage(_ disc: DiscInfo) -> some View {
        InfoGroup(title: "Storage") {
            if let used = disc.usedSize, let total = disc.discSize, total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    UsageBar(fraction: Double(used) / Double(total))
                    Text("\(byteText(used)) of \(byteText(total)) disc used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            InfoRow("Format", game.container)
            InfoRow("On disk", byteText(game.bytesOnDisk))
            if let url = game.fileURL {
                let parts = Naming.splitParts(of: url).count
                if parts > 1 { InfoRow("Split", "\(parts) parts") }
                InfoRow(label: "Location") {
                    Button(url.deletingLastPathComponent().lastPathComponent) { model.reveal(game) }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url.path)
                }
            } else if case .partition(_, let slot) = game.location {
                InfoRow("Drive slot", "\(slot)")
            }
        }
    }

    @ViewBuilder
    private func partitions(_ disc: DiscInfo) -> some View {
        if !disc.partitions.isEmpty {
            InfoGroup(title: "Partitions") {
                ForEach(disc.partitions) { partition in
                    InfoRow(partition.label, byteText(partition.sizeBytes))
                }
            }
        }
    }
}
