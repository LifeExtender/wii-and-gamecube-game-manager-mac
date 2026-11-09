import Foundation
import WiiKit

/// Comparing the computer's libraries with connected drives, and offering what's missing.
extension AppModel {
    /// Games from libraries that are still reachable. An unplugged library can't be copied from.
    private var computerLibraries: [[Game]] {
        libraries.filter { list in
            guard !list.isDrive else { return false }
            guard let folder = list.source.folder else { return true }
            return FileManager.default.fileExists(atPath: folder.path)
        }.map(\.games)
    }

    /// Everything in the user's libraries that this drive doesn't hold and could run.
    func addableGames(to drive: GameList) -> [Game] {
        LibrarySync.missing(from: computerLibraries, on: drive.games, wiiOnly: drive.source.device != nil)
    }

    private func syncKey(for drive: GameList) -> String { drive.syncKey ?? drive.name }

    /// One prompt per connected drive with games to offer. Games already being written are left out.
    var syncPrompts: [SyncPrompt] {
        guard settings.suggestMissing else { return [] }
        let inFlight = Set(queue.jobs.map(\.gameID))
        return libraries.filter { $0.isDrive && $0.hasLoaded && $0.message == nil }.compactMap { drive in
            let declined = Set(settings.declinedMissing[syncKey(for: drive)] ?? [])
            let games = LibrarySync.missing(
                from: computerLibraries, on: drive.games, excluding: declined, wiiOnly: drive.source.device != nil
            )
            .filter { !inFlight.contains($0.gameID) }
            .sorted { displayTitle(for: $0).localizedCaseInsensitiveCompare(displayTitle(for: $1)) == .orderedAscending }
            return games.isEmpty ? nil : SyncPrompt(drive: drive, games: games)
        }
    }

    /// A drive's own page only offers that drive; an empty drive already has its own call to action.
    func syncPrompt(on list: GameList) -> SyncPrompt? {
        let prompts = syncPrompts
        guard list.isDrive else { return prompts.first }
        return list.games.isEmpty ? nil : prompts.first { $0.drive === list }
    }

    /// Stops offering these games for this drive. Games added to a library later still prompt.
    func decline(_ games: [Game], on drive: GameList) {
        guard !games.isEmpty else { return }
        let key = syncKey(for: drive)
        settings.declinedMissing[key] = Array(Set(settings.declinedMissing[key] ?? []).union(games.map(\.identity))).sorted()
    }

    func hasDeclined(on drive: GameList) -> Bool {
        !(settings.declinedMissing[syncKey(for: drive)] ?? []).isEmpty
    }

    func resetDeclined(on drive: GameList) {
        settings.declinedMissing[syncKey(for: drive)] = nil
    }

    /// Expected size on a drive, remembered per game. Wii games are scrubbed; GameCube games are full ISOs.
    func estimatedSizes(of games: [Game]) async -> [String: Int64] {
        let unknown = games.filter { sizeEstimates[$0.id] == nil }
        let wii = unknown.filter { $0.platform == "Wii" }.map(\.id)
        let scrubbed = (try? await engine.scrubbedSizes(sources: wii)) ?? [:]
        for game in unknown {
            sizeEstimates[game.id] = game.platform == "GameCube" ? Limits.gameCubeDiscBytes : (scrubbed[game.id] ?? game.bytesOnDisk)
        }
        return sizeEstimates
    }
}
