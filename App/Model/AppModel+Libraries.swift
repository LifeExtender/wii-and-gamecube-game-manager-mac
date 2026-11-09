import AppKit
import WiiKit

extension AppModel {
    var currentList: GameList? {
        guard case .library(let id) = pane else { return nil }
        return libraries.first { $0.id == id }
    }

    var folderLibraries: [GameList] { libraries.filter { !$0.isDrive } }

    func restoreLibraries() {
        restoreMissingLibraries()
        pane = libraries.first.map { .library($0.id) }
    }

    /// Also runs when disks change, so a library on a drive that was absent at launch comes back.
    func restoreMissingLibraries() {
        for path in settings.libraries where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if !libraries.contains(where: { $0.source.folder == url }) { add(url: url, persist: false, select: false) }
        }
    }

    @discardableResult
    func add(url: URL, persist: Bool = true, select: Bool = true) -> GameList {
        if let existing = libraries.first(where: { $0.source.folder == url }) {
            if select { pane = .library(existing.id) }
            return existing
        }
        let isFolder = Self.isFolder(url)
        let list = GameList(source: isFolder ? .folder(url) : .files([url]), name: url.lastPathComponent)
        libraries.append(list)
        if persist, isFolder { settings.libraries.append(url.path) }
        reload(list)
        if select { pane = .library(list.id) }
        return list
    }

    /// Folders become libraries of their own; loose disc images share one.
    func addByDropping(_ urls: [URL]) {
        var looseFiles: [URL] = []
        for url in urls {
            if Self.isFolder(url) { add(url: url) } else { looseFiles.append(url) }
        }
        guard !looseFiles.isEmpty else { return }
        let name = looseFiles.count == 1 ? looseFiles[0].lastPathComponent : "\(looseFiles.count) Disc Images"
        let list = GameList(source: .files(looseFiles), name: name)
        libraries.append(list)
        reload(list)
        pane = .library(list.id)
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose a folder of games, or individual disc images."
        guard panel.runModal() == .OK else { return }
        addByDropping(panel.urls)
    }

    func remove(_ list: GameList) {
        libraries.removeAll { $0.id == list.id }
        if let folder = list.source.folder { settings.libraries.removeAll { $0 == folder.path } }
        if pane == .library(list.id) { pane = libraries.first.map { .library($0.id) } }
    }

    func rows(for list: GameList) -> [GameRow] {
        var locations: [String: [String]] = [:]
        for other in libraries where other !== list {
            for game in other.games { locations[game.gameID, default: []].append(other.name) }
        }
        var rows = list.games.map { game in
            GameRow(
                game: game, title: displayTitle(for: game),
                notes: locations[game.gameID].map { "Also in \($0.joined(separator: ", "))" } ?? "")
        }
        if let platform = list.platformFilter { rows = rows.filter { $0.platform == platform } }
        if let region = list.regionFilter { rows = rows.filter { $0.region == region } }
        let query = list.search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            rows = rows.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.gameID.localizedCaseInsensitiveContains(query) }
        }
        rows.sort(using: list.sortOrder)
        return rows
    }

    func reload(_ list: GameList) {
        list.loadGeneration += 1
        let generation = list.loadGeneration
        list.isLoading = true
        list.message = nil
        // Drives are always read in full, because games sit in per-game folders.
        let recursive = settings.recurse || list.isDrive
        let source = list.source
        Task {
            do {
                let contents = try await read(source, recursive: recursive)
                guard generation == list.loadGeneration else { return }
                list.games = contents.games
                list.space = contents.space
                list.hasLoaded = true
                list.selection.formIntersection(contents.games.map(\.id))
            } catch {
                guard generation == list.loadGeneration else { return }
                list.games = []
                list.space = nil
                list.message = error.localizedDescription
            }
            list.isLoading = false
        }
    }

    private func read(_ source: ListSource, recursive: Bool) async throws -> PartitionContents {
        switch source {
        case .folder(let url):
            return PartitionContents(games: await withDiscNumbers(try await engine.scan(folder: url, recursive: recursive)), space: nil)
        case .files(let urls):
            return PartitionContents(games: await withDiscNumbers(try await engine.scan(files: urls)), space: nil)
        case .partition(let device, _):
            return try await engine.readPartition(device)
        }
    }

    private func withDiscNumbers(_ games: [Game]) async -> [Game] {
        let resolved = await engine.resolvingDiscNumbers(games, known: discNumbers)
        for game in resolved where game.platform == "GameCube" { discNumbers[game.discCacheKey] = game.discNumber }
        return resolved
    }

    func reloadAll() {
        discInfoCache.removeAll()
        libraries.forEach(reload)
    }

    /// Keeps drive pages and "on drive" marks current during a long queue. Raw WBFS drives wait
    /// for the queue to finish, because they can't be read safely while being written.
    func reloadMountedDrives() {
        libraries.filter { $0.isDrive && $0.source.device == nil }.forEach(reload)
    }

    func selected(in list: GameList) -> [Game] {
        list.games.filter { list.selection.contains($0.id) }
    }

    func games(ids: Set<String>, in list: GameList) -> [Game] {
        list.games.filter { ids.contains($0.id) }
    }

    func selectMissing(from other: GameList, in list: GameList) {
        let present = Set(other.games.map(\.gameID))
        list.selection = Set(list.games.filter { !present.contains($0.gameID) }.map(\.id))
    }

    /// Plain click selects one, Command toggles, Shift extends from the last plain click.
    func click(_ id: String, in list: GameList, ordered: [String]) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if list.selection.contains(id) { list.selection.remove(id) } else { list.selection.insert(id) }
            list.selectionAnchor = id
        } else if flags.contains(.shift), let anchor = list.selectionAnchor,
            let from = ordered.firstIndex(of: anchor), let to = ordered.firstIndex(of: id)
        {
            list.selection = Set(ordered[min(from, to)...max(from, to)])
        } else {
            list.selection = [id]
            list.selectionAnchor = id
        }
    }
}
