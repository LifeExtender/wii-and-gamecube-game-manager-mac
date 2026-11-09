import Foundation
import WiiKit

/// Titles, the game database and cover art, all from GameTDB.
extension AppModel {
    private var titlesURL: URL { Self.supportFolder.appendingPathComponent("titles-\(settings.titleLanguage).txt") }
    private var databaseURL: URL { Self.supportFolder.appendingPathComponent("wiitdb.xml") }
    private var customTitlesURL: URL { Self.supportFolder.appendingPathComponent("custom_titles.json") }

    func loadCustomTitles() {
        guard let data = try? Data(contentsOf: customTitlesURL),
            let saved = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        customTitles = saved
    }

    func loadTitlesFromDisk() {
        titles = TitleDatabase(text: (try? String(contentsOf: titlesURL, encoding: .utf8)) ?? "")
    }

    func loadInfoFromDisk() async {
        let file = databaseURL
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let language = settings.titleLanguage
        info = await Task.detached(priority: .utility) {
            GameInfoParser.parse(fileAt: file, language: language)
        }.value
    }

    func displayTitle(for game: Game) -> String {
        customTitles[game.gameID] ?? titles.title(for: game.gameID) ?? game.discName
    }

    func setCustomTitle(_ title: String?, for gameID: String) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        customTitles[gameID] = (trimmed?.isEmpty == false) ? trimmed : nil
        if let data = try? JSONEncoder().encode(customTitles) { try? data.write(to: customTitlesURL, options: .atomic) }
    }

    func updateTitles() {
        let language = settings.titleLanguage
        let file = titlesURL
        queue.enqueue(title: "Title list (\(language))", action: "Update titles") { _ in
            try await GameTDB.downloadTitles(language: language, to: file)
        } completion: { [weak self] _ in
            self?.loadTitlesFromDisk()
        }
    }

    func updateDatabase() {
        let file = databaseURL
        queue.enqueue(title: "Game database", action: "Update database") { _ in
            try await GameTDB.downloadDatabase(to: file)
        } completion: { [weak self] _ in
            Task { await self?.loadInfoFromDisk() }
        }
    }

    func coverFolder(_ kind: CoverKind) -> URL {
        if let path = settings.coverFolders[kind.rawValue] { return URL(fileURLWithPath: path, isDirectory: true) }
        return Self.supportFolder.appendingPathComponent("Covers/\(kind.rawValue)", isDirectory: true)
    }

    /// The ID comes from the disc itself, so it is made safe before becoming part of a path.
    func coverFile(_ kind: CoverKind, gameID: String) -> URL {
        coverFolder(kind).appendingPathComponent("\(Naming.safeComponent(gameID)).png")
    }

    func hasCover(_ kind: CoverKind, gameID: String) -> Bool {
        FileManager.default.fileExists(atPath: coverFile(kind, gameID: gameID).path)
    }

    private func announceArtwork(_ kind: CoverKind, gameID: String) {
        artworkRevision += 1
        NotificationCenter.default.post(name: .artworkSaved, object: "\(kind.rawValue)/\(gameID)")
    }

    /// Fetches art as it comes on screen, one request at a time to stay light on GameTDB.
    func requestArtwork(_ kind: CoverKind, gameID: String) {
        guard settings.autoDownloadCovers, !hasCover(kind, gameID: gameID),
            artRequested.insert("\(kind.rawValue)/\(gameID)").inserted
        else { return }
        artQueue.append((kind, gameID))
        guard artTask == nil else { return }
        artTask = Task {
            while !artQueue.isEmpty {
                let (nextKind, nextID) = artQueue.removeFirst()
                let saved = (try? await GameTDB.downloadCover(
                    kind: nextKind, gameID: nextID, language: settings.titleLanguage,
                    preferCustomDisc: settings.preferCustomDisc, highQualityFull: settings.highQualityFull,
                    to: coverFile(nextKind, gameID: nextID))) ?? false
                if saved { announceArtwork(nextKind, gameID: nextID) }
            }
            artTask = nil
        }
    }

    func downloadCovers(gameIDs: [String], kinds: [CoverKind]) {
        var wanted: [(CoverKind, String, URL)] = []
        for id in gameIDs {
            for kind in kinds where !hasCover(kind, gameID: id) { wanted.append((kind, id, coverFile(kind, gameID: id))) }
        }
        guard !wanted.isEmpty else {
            notice = Notice(title: "Nothing to Download", message: "That artwork is already saved.")
            return
        }
        let batch = wanted
        let language = settings.titleLanguage
        let customDisc = settings.preferCustomDisc
        let highQuality = settings.highQualityFull
        queue.enqueue(title: "\(batch.count) images", action: "Download artwork") { [weak self] context in
            var done = 0
            for (kind, id, destination) in batch {
                if context.cancel.isCancelled { throw OperationCancelled() }
                let saved = try await GameTDB.downloadCover(
                    kind: kind, gameID: id, language: language, preferCustomDisc: customDisc,
                    highQualityFull: highQuality, to: destination)
                done += 1
                context.progress(ToolProgress(fraction: Double(done) / Double(batch.count), line: ""))
                if saved { await self?.announceArtwork(kind, gameID: id) }
            }
        }
    }

    func missingArtworkRows() -> [MissingArtRow] {
        var seen = Set<String>()
        var rows: [MissingArtRow] = []
        for list in libraries {
            for game in list.games where seen.insert(game.gameID).inserted {
                let row = MissingArtRow(
                    gameID: game.gameID, title: displayTitle(for: game),
                    flat: hasCover(.flat, gameID: game.gameID), threeD: hasCover(.threeD, gameID: game.gameID),
                    disc: hasCover(.disc, gameID: game.gameID), full: hasCover(.full, gameID: game.gameID))
                if !row.complete { rows.append(row) }
            }
        }
        return rows.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
