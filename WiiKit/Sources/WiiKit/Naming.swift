import Foundation

public enum Naming {
    public static func safeComponent(_ raw: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        let scalars = raw.unicodeScalars.filter { !banned.contains($0) }
        var text = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let last = text.last, last == "." || last == " " { text.removeLast() }
        while let first = text.first, first == "." || first == " " { text.removeFirst() }
        if text.count > 80 { text = String(text.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return text.isEmpty ? "Untitled" : text
    }

    /// `Title [GAMEID]/GAMEID.wbfs` is the layout current USB loaders expect.
    public static func outputURL(
        base: URL, gameID: String, title: String, format: OutputFormat,
        naming: NamingStyle, subdirectories: Bool
    ) -> URL {
        let id = safeComponent(gameID)
        let name = safeComponent(title)
        var folder = base
        if subdirectories { folder.appendPathComponent("\(name) [\(id)]", isDirectory: true) }
        let stem = (naming == .gameIDTitle && !subdirectories) ? "\(id)_\(name)" : id
        return folder.appendingPathComponent("\(stem).\(format.fileExtension)")
    }

    /// `wit` expands `%` escapes in destination paths, so literal percent signs must be doubled.
    public static func escapedDestination(_ path: String) -> String {
        path.replacingOccurrences(of: "%", with: "%%")
    }

    /// Nintendont and USB Loader GX read GameCube discs from `/games/Title [ID]/game.iso`.
    public static func gameCubeURL(root: URL, gameID: String, title: String, discNumber: Int) -> URL {
        let folder = "\(safeComponent(title)) [\(safeComponent(gameID))]"
        let file = discNumber > 0 ? "disc\(discNumber + 1).iso" : "game.iso"
        return root.appendingPathComponent("games", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(file)
    }

    public static func wiiURL(root: URL, gameID: String, title: String) -> URL {
        outputURL(
            base: root.appendingPathComponent("wbfs", isDirectory: true), gameID: gameID, title: title,
            format: .wbfs, naming: .gameID, subdirectories: true)
    }

    public static func splitParts(of url: URL, fileManager: FileManager = .default) -> [URL] {
        var parts = [url]
        var index = 1
        while true {
            let candidate: URL
            if url.pathExtension.lowercased() == "wbfs" {
                candidate = url.deletingPathExtension().appendingPathExtension("wbf\(index)")
            } else {
                candidate = URL(fileURLWithPath: url.path + ".\(index)")
            }
            guard fileManager.fileExists(atPath: candidate.path) else { break }
            parts.append(candidate)
            index += 1
        }
        return parts
    }
}
