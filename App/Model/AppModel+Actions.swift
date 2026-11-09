import AppKit
import UniformTypeIdentifiers
import WiiKit

/// Everything the user can do to a game: each action queues one job per game.
extension AppModel {
    func discInfo(for game: Game) async throws -> DiscInfo {
        if let cached = discInfoCache[game.id] { return cached }
        let info = try await engine.discInfo(source: game.id)
        discInfoCache[game.id] = info
        return info
    }

    /// GameCube discs carry no hash tree, so only Wii discs can be verified.
    func enqueueVerify(_ games: [Game]) {
        let engine = engine
        for game in games where game.platform == "Wii" {
            let id = game.id
            verification[id] = .running
            queue.enqueue(title: displayTitle(for: game), action: "Verify") { context in
                try await engine.verify(source: id, cancel: context.cancel, progress: context.progress)
            } completion: { [weak self] state in
                switch state {
                case .finished: self?.verification[id] = .passed
                case .failed(let reason): self?.verification[id] = .failed(reason)
                default: self?.verification[id] = nil
                }
            }
        }
    }

    func destinations(excluding list: GameList) -> [GameList] {
        libraries.filter { $0 !== list && ($0.source.device != nil || $0.source.folder != nil) }
    }

    func send(_ games: [Game], to destination: GameList) {
        if destination.isDrive {
            enqueueLoaderCopies(games, to: destination)
        } else if let folder = destination.source.folder {
            activeSheet = .convert(ConvertDraft(games: games, format: .wbfs, destination: folder))
        }
    }

    /// Writes games where USB loaders look for them: Wii to `/wbfs`, GameCube to `/games`.
    func enqueueLoaderCopies(_ games: [Game], to drive: GameList) {
        if let device = drive.source.device {
            let wii = games.filter { $0.platform == "Wii" }
            if wii.count < games.count {
                notice = Notice(title: "GameCube Games Skipped", message: "GameCube games can't run from a WBFS drive. Use a FAT32 drive for those.")
            }
            enqueueAdd(wii, toPartition: device)
            return
        }
        guard let root = drive.source.folder else { return }
        let engine = engine
        let copyMode = settings.copyMode
        for game in games {
            let title = displayTitle(for: game)
            queue.enqueue(gameID: game.gameID, title: title, action: "Add to \(drive.name)") { context in
                if game.platform == "GameCube" {
                    let output = Naming.gameCubeURL(root: root, gameID: game.gameID, title: title, discNumber: game.discNumber)
                    try await engine.convertGameCube(
                        source: game.id, destination: output, cancel: context.cancel, progress: context.progress)
                } else {
                    let output = Naming.wiiURL(root: root, gameID: game.gameID, title: title)
                    try await engine.convert(
                        source: game.id, destination: output, format: .wbfs, split: .fourGB, copyMode: copyMode,
                        cancel: context.cancel, progress: context.progress)
                }
            }
        }
    }

    func enqueueConvert(_ draft: ConvertDraft, destination: URL) {
        let engine = engine
        let copyMode = settings.copyMode
        let format = draft.format
        let split = draft.split
        for game in draft.games {
            let title = displayTitle(for: game)
            let output = Naming.outputURL(
                base: destination, gameID: game.gameID, title: title, format: format,
                naming: draft.naming, subdirectories: draft.subdirectories)
            let verb = game.isOnPartition ? "Extract" : "Create"
            queue.enqueue(gameID: game.gameID, title: title, action: "\(verb) .\(format.fileExtension)") { context in
                if game.platform == "GameCube", format == .iso {
                    try await engine.convertGameCube(
                        source: game.id, destination: output, cancel: context.cancel, progress: context.progress)
                } else {
                    try await engine.convert(
                        source: game.id, destination: output, format: format, split: split, copyMode: copyMode,
                        cancel: context.cancel, progress: context.progress)
                }
            }
        }
    }

    func enqueueResplit(_ games: [Game], split: SplitMode) {
        let engine = engine
        for game in games {
            guard let file = game.fileURL else { continue }
            queue.enqueue(gameID: game.gameID, title: displayTitle(for: game), action: "Resplit") { context in
                try await engine.resplit(file: file, split: split, cancel: context.cancel, progress: context.progress)
            }
        }
    }

    func enqueueTransfer(_ draft: TransferDraft, destination: URL) {
        let move = draft.move
        for game in draft.games {
            let title = displayTitle(for: game)
            let folder = draft.subdirectories
                ? destination.appendingPathComponent("\(Naming.safeComponent(title)) [\(Naming.safeComponent(game.gameID))]")
                : destination
            queue.enqueue(gameID: game.gameID, title: title, action: move ? "Move" : "Copy") { context in
                try await Task.detached {
                    try FileOps.transfer(game: game, to: folder, move: move, cancel: context.cancel, progress: context.progress)
                }.value
            }
        }
    }

    func enqueueAdd(_ games: [Game], toPartition device: String) {
        let engine = engine
        let copyMode = settings.copyMode
        for game in games {
            queue.enqueue(gameID: game.gameID, title: displayTitle(for: game), action: "Add to drive") { context in
                try await engine.addToPartition(
                    device: device, sources: [game.id], copyMode: copyMode,
                    cancel: context.cancel, progress: context.progress)
            }
        }
    }

    func confirmDelete(_ games: [Game]) {
        let alert = NSAlert()
        let onDrive = games.first?.isOnPartition == true
        alert.messageText = games.count == 1 ? "Delete \(displayTitle(for: games[0]))?" : "Delete \(games.count) games?"
        alert.informativeText = onDrive
            ? "These games will be removed from the WBFS drive. This cannot be undone."
            : "These files will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: onDrive ? "Delete" : "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let engine = engine
        for game in games {
            let title = displayTitle(for: game)
            switch game.location {
            case .partition(let device, _):
                queue.enqueue(gameID: game.gameID, title: title, action: "Remove from drive") { _ in
                    try await engine.removeFromPartition(device: device, gameID: game.gameID)
                }
            case .file:
                queue.enqueue(gameID: game.gameID, title: title, action: "Move to Trash") { _ in
                    try FileOps.moveToTrash(game: game)
                }
            }
        }
    }

    func reveal(_ game: Game) {
        if let url = game.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // MARK: Export

    private func exportCSV(named name: String, rows: [[String]]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSV.encode(rows).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            notice = Notice(title: "Could Not Save", message: error.localizedDescription)
        }
    }

    func exportGames(from list: GameList, ids: Set<String>?) {
        let chosen = rows(for: list).filter { ids?.contains($0.id) ?? true }
        let header = ["GameID", "Game Title", "File Size", "Format", "Platform", "Region", "Directory", "Filename", "Notes"]
        let body = chosen.map {
            [$0.gameID, $0.title, String($0.sizeBytes), $0.format, $0.platform, $0.region, $0.directory, $0.filename, $0.notes]
        }
        exportCSV(named: "\(list.name).csv", rows: [header] + body)
    }

    func exportLog() {
        let formatter = ISO8601DateFormatter()
        let body = queue.log.map { [$0.gameID, $0.title, $0.action, $0.result, formatter.string(from: $0.date)] }
        exportCSV(named: "Activity.csv", rows: [["GameID", "Game Title", "Action", "Result", "Date/Time"]] + body)
    }

    func exportMissingArtwork(_ rows: [MissingArtRow]) {
        let body = rows.map {
            [$0.gameID, $0.title, $0.flat ? "Yes" : "No", $0.threeD ? "Yes" : "No", $0.disc ? "Yes" : "No", $0.full ? "Yes" : "No"]
        }
        exportCSV(named: "Missing Artwork.csv", rows: [["GameID", "Game Title", "Flat", "3D", "Disc", "Full"]] + body)
    }
}
