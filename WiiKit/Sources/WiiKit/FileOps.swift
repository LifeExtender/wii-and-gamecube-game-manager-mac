import Foundation

public enum FileOps {
    /// Copies or moves a game, including any split parts, into `folder`.
    public static func transfer(
        game: Game, to folder: URL, move: Bool, cancel: CancelToken? = nil,
        progress: (@Sendable (ToolProgress) -> Void)? = nil
    ) throws {
        guard let source = game.fileURL else {
            throw PreflightFailure("Games on a WBFS drive are extracted, not copied as files.")
        }
        let fm = FileManager.default
        let parts = Naming.splitParts(of: source)
        let targets = parts.map { folder.appendingPathComponent($0.lastPathComponent) }
        let sizes = try parts.map { try fileSize($0) }
        let total = sizes.reduce(0, +)

        for target in targets where fm.fileExists(atPath: target.path) {
            throw PreflightFailure("\(target.lastPathComponent) already exists in the destination.")
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let sameVolume = sameVolume(source, folder)
        if move && sameVolume {
            for (part, target) in zip(parts, targets) { try fm.moveItem(at: part, to: target) }
            targets.forEach(removeAppleDoubleCompanions)
            progress?(ToolProgress(fraction: 1, line: "Moved"))
            return
        }

        if let volume = VolumeFacts.of(folder) {
            if volume.isFAT32, let oversized = zip(parts, sizes).first(where: { $0.1 > Limits.fat32MaxFileBytes }) {
                throw PreflightFailure(
                    "\(oversized.0.lastPathComponent) is too large for a FAT32 drive. Use Create .wbfs with a 4 GB split instead.")
            }
            if volume.availableBytes < total {
                throw PreflightFailure("The destination does not have enough free space.")
            }
        }

        var written: Int64 = 0
        var finished: [URL] = []
        do {
            for (part, target) in zip(parts, targets) {
                try copyFile(part, to: target, cancel: cancel) { bytes in
                    written += bytes
                    progress?(ToolProgress(fraction: total > 0 ? Double(written) / Double(total) : 1, line: ""))
                }
                finished.append(target)
            }
        } catch {
            for target in finished { try? fm.removeItem(at: target) }
            throw error
        }

        if move {
            for part in parts { try fm.removeItem(at: part) }
        }
        targets.forEach(removeAppleDoubleCompanions)
    }

    /// macOS writes hidden `._name` files beside everything it creates on FAT32, and USB loaders
    /// scanning for games can trip over them. Removes only those companions of `url` and of its
    /// parent folders up to the volume root, and only files carrying the AppleDouble signature.
    public static func removeAppleDoubleCompanions(of url: URL) {
        guard VolumeFacts.of(url)?.isFAT32 == true else { return }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        var targets = isDirectory.boolValue ? [url] : Naming.splitParts(of: url)
        var folder = url.deletingLastPathComponent()
        while folder.path.count > 1, (try? folder.resourceValues(forKeys: [.isVolumeKey]).isVolume) != true {
            targets.append(folder)
            folder.deleteLastPathComponent()
        }
        for target in targets {
            let companion = target.deletingLastPathComponent().appendingPathComponent("._\(target.lastPathComponent)")
            guard let handle = try? FileHandle(forReadingFrom: companion) else { continue }
            let signature = try? handle.read(upToCount: 4)
            try? handle.close()
            if signature == Data([0x00, 0x05, 0x16, 0x07]) { try? FileManager.default.removeItem(at: companion) }
        }
    }

    public static func moveToTrash(game: Game) throws {
        guard let source = game.fileURL else { return }
        for part in Naming.splitParts(of: source) {
            try FileManager.default.trashItem(at: part, resultingItemURL: nil)
        }
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key = URLResourceKey.volumeIdentifierKey
        guard let first = try? a.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject,
            let second = try? b.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject
        else { return false }
        return first.isEqual(second)
    }

    /// Writes to a `.partial` name first so an interrupted copy never looks like a finished game.
    private static func copyFile(
        _ source: URL, to target: URL, cancel: CancelToken?, wrote: (Int64) -> Void
    ) throws {
        let fm = FileManager.default
        let partial = URL(fileURLWithPath: target.path + ".partial")
        guard fm.createFile(atPath: partial.path, contents: nil) else {
            throw PreflightFailure("Could not create a file in the destination.")
        }
        do {
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: partial)
            defer { try? output.close() }
            while true {
                if cancel?.isCancelled == true { throw OperationCancelled() }
                guard let chunk = try input.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
                wrote(Int64(chunk.count))
            }
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
        try fm.moveItem(at: partial, to: target)
    }
}
