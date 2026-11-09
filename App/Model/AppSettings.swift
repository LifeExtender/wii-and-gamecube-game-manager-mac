import AppKit
import WiiKit

enum LibraryLayout: String, Codable { case grid, list }

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct AppSettings: Codable {
    var titleLanguage = "EN"
    var recurse = true
    var copyMode: CopyMode = .gamePartition
    var coverFolders: [String: String] = [:]
    var preferCustomDisc = false
    var highQualityFull = false
    var autoDownloadCovers = true
    var libraries: [String] = []
    var layout: LibraryLayout = .grid
    var appearance: AppearanceMode = .system
    var coverSize: Double = 160
    var suggestMissing = true
    var declinedMissing: [String: [String]] = [:]

    init() {}

    /// Falls back to the default for any key that is missing or unreadable, so settings saved by
    /// another version of the app are never discarded wholesale.
    init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? saved.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        titleLanguage = value(.titleLanguage, defaults.titleLanguage)
        recurse = value(.recurse, defaults.recurse)
        copyMode = value(.copyMode, defaults.copyMode)
        coverFolders = value(.coverFolders, defaults.coverFolders)
        preferCustomDisc = value(.preferCustomDisc, defaults.preferCustomDisc)
        highQualityFull = value(.highQualityFull, defaults.highQualityFull)
        autoDownloadCovers = value(.autoDownloadCovers, defaults.autoDownloadCovers)
        libraries = value(.libraries, defaults.libraries)
        layout = value(.layout, defaults.layout)
        appearance = value(.appearance, defaults.appearance)
        coverSize = value(.coverSize, defaults.coverSize)
        suggestMissing = value(.suggestMissing, defaults.suggestMissing)
        declinedMissing = value(.declinedMissing, defaults.declinedMissing)
    }
}
