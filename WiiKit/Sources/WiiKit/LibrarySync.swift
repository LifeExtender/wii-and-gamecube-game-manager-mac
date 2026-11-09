import Foundation

public enum LibrarySync {
    /// Games held in any of `libraries` but absent from `drive`, each listed once.
    /// - Parameters:
    ///   - ignored: identities the user has already declined for this drive.
    ///   - wiiOnly: set for raw WBFS drives, which can't run GameCube discs.
    public static func missing(
        from libraries: [[Game]], on drive: [Game], excluding ignored: Set<String> = [], wiiOnly: Bool = false
    ) -> [Game] {
        var seen = Set(drive.map(\.identity)).union(ignored)
        var result: [Game] = []
        for library in libraries {
            for game in library where seen.insert(game.identity).inserted {
                if !wiiOnly || game.platform == "Wii" { result.append(game) }
            }
        }
        return result
    }
}
