import Foundation

public enum CoverKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case flat, threeD, disc, full
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .flat: return "Flat"
        case .threeD: return "3D"
        case .disc: return "Disc"
        case .full: return "Full"
        }
    }

    func remoteFolders(preferCustomDisc: Bool, highQualityFull: Bool) -> [String] {
        switch self {
        case .flat: return ["cover"]
        case .threeD: return ["cover3D"]
        case .disc: return preferCustomDisc ? ["disccustom", "disc"] : ["disc", "disccustom"]
        case .full: return highQualityFull ? ["coverfullHQ", "coverfull"] : ["coverfull", "coverfullHQ"]
        }
    }
}

public enum GameTDB {
    public static let languages = ["EN", "ES", "NL", "FR", "DE", "IT", "KO", "JA", "PT"]
    public static let databaseURL = URL(string: "https://www.gametdb.com/wiitdb.zip")!
    private static let userAgent = "WiiGameManager-Mac/1.0"

    public static func titlesURL(language: String) -> URL {
        URL(string: "https://www.gametdb.com/titles.txt?LANG=\(language)")!
    }

    /// The fourth character of a game ID is its region. Art is filed under a language folder.
    public static func artRegions(gameID: String, language: String) -> [String] {
        let characters = Array(gameID)
        let code = characters.count >= 4 ? characters[3] : "P"
        let primary: [String]
        switch code {
        case "E", "N": primary = ["US"]
        case "J": primary = ["JA"]
        case "K", "Q", "T": primary = ["KO"]
        case "W": primary = ["ZHTW", "ZHCN"]
        case "D": primary = ["DE"]
        case "F": primary = ["FR"]
        case "S": primary = ["ES"]
        case "I": primary = ["IT"]
        case "H": primary = ["NL"]
        case "U": primary = ["AU"]
        default: primary = language == "JA" || language == "KO" ? ["EN"] : [language]
        }
        var seen = Set<String>()
        return (primary + ["EN", "US", "JA"]).filter { seen.insert($0).inserted }
    }

    public static func coverCandidates(
        kind: CoverKind, gameID: String, language: String,
        preferCustomDisc: Bool = false, highQualityFull: Bool = false
    ) -> [URL] {
        // The ID comes from the disc itself, so a damaged or unusual image can put anything here.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        guard let safeID = gameID.addingPercentEncoding(withAllowedCharacters: allowed) else { return [] }
        let folders = kind.remoteFolders(preferCustomDisc: preferCustomDisc, highQualityFull: highQualityFull)
        return folders.flatMap { folder in
            artRegions(gameID: gameID, language: language).compactMap { region in
                URL(string: "https://art.gametdb.com/wii/\(folder)/\(region)/\(safeID).png")
            }
        }
    }

    public static func download(_ url: URL, session: URLSession = .shared) async throws -> (URL, HTTPURLResponse?) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (file, response) = try await session.download(for: request)
        return (file, response as? HTTPURLResponse)
    }

    /// Returns false when the artwork does not exist. Requests run one at a time to stay light on the server.
    public static func downloadCover(
        kind: CoverKind, gameID: String, language: String, preferCustomDisc: Bool, highQualityFull: Bool,
        to destination: URL, session: URLSession = .shared
    ) async throws -> Bool {
        let candidates = coverCandidates(
            kind: kind, gameID: gameID, language: language,
            preferCustomDisc: preferCustomDisc, highQualityFull: highQualityFull)
        for url in candidates {
            let (file, response) = try await download(url, session: session)
            guard response?.statusCode == 200 else {
                try? FileManager.default.removeItem(at: file)
                continue
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file, to: destination)
            return true
        }
        return false
    }

    public static func downloadTitles(language: String, to destination: URL) async throws {
        let (file, response) = try await download(titlesURL(language: language))
        guard response?.statusCode == 200 else { throw PreflightFailure("GameTDB did not return a title list.") }
        try replace(destination, with: file)
    }

    public static func downloadDatabase(to xmlDestination: URL) async throws {
        let fm = FileManager.default
        let (zip, response) = try await download(databaseURL)
        defer { try? fm.removeItem(at: zip) }
        guard response?.statusCode == 200 else { throw PreflightFailure("GameTDB did not return its database.") }
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: folder) }
        let result = try await runTool(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, folder.path])
        guard result.exitCode == 0 else { throw PreflightFailure("The database archive could not be unpacked.") }
        try replace(xmlDestination, with: folder.appendingPathComponent("wiitdb.xml"))
    }

    private static func replace(_ destination: URL, with file: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: file, to: destination)
    }
}
