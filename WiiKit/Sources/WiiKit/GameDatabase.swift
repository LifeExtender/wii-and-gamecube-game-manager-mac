import Foundation

public struct TitleDatabase: Sendable {
    private let titles: [String: String]

    public init(titles: [String: String] = [:]) { self.titles = titles }

    public init(text: String) {
        var map: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.range(of: " = ") else { continue }
            let id = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            guard id != "TITLES" else { continue }
            map[id] = line[separator.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        titles = map
    }

    public var isEmpty: Bool { titles.isEmpty }

    public func title(for gameID: String) -> String? {
        titles[gameID] ?? titles[String(gameID.prefix(4))]
    }
}

public struct GameInfo: Codable, Sendable, Equatable {
    public var title = ""
    public var synopsis = ""
    public var genre = ""
    public var developer = ""
    public var publisher = ""
    public var year = ""
    public var players = ""
    public var region = ""
    public var rating = ""
    public var onlinePlayers = ""
    public var languages = ""
    public var controls: [String] = []

    /// Turns the database's control identifiers into the names printed on the box.
    public static func controllerName(_ type: String) -> String {
        let known = [
            "wiimote": "Wii Remote", "nunchuk": "Nunchuk", "nunchuck": "Nunchuk",
            "classiccontroller": "Classic Controller", "gamecube": "GameCube Controller",
            "balanceboard": "Balance Board", "wheel": "Wii Wheel", "motionplus": "Wii MotionPlus",
            "wiispeak": "Wii Speak", "zapper": "Wii Zapper", "dancepad": "Dance Pad", "udraw": "uDraw Tablet",
        ]
        return known[type.lowercased()] ?? type.prefix(1).uppercased() + type.dropFirst()
    }
}

/// Streams wiitdb.xml into a per-game summary for one language, falling back to English.
public final class GameInfoParser: NSObject, XMLParserDelegate {
    private let language: String
    private var result: [String: GameInfo] = [:]
    private var current: GameInfo?
    private var gameID = ""
    private var text = ""
    private var localeRank = 0
    private var bestTitleRank = 0
    private var bestSynopsisRank = 0
    private var requiredControls: [String] = []
    private var optionalControls: [String] = []

    private init(language: String) { self.language = language }

    public static func parse(fileAt url: URL, language: String) -> [String: GameInfo] {
        guard let parser = XMLParser(contentsOf: url) else { return [:] }
        let delegate = GameInfoParser(language: language)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    public static func parse(data: Data, language: String) -> [String: GameInfo] {
        let parser = XMLParser(data: data)
        let delegate = GameInfoParser(language: language)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    public func parser(
        _ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        switch element {
        case "game":
            current = GameInfo()
            gameID = ""
            bestTitleRank = 0
            bestSynopsisRank = 0
            requiredControls = []
            optionalControls = []
        case "locale":
            let lang = attributes["lang"]
            localeRank = lang == language ? 2 : (lang == "EN" ? 1 : 0)
        case "date":
            if let year = attributes["year"], !year.isEmpty { current?.year = year }
        case "input":
            if let players = attributes["players"], !players.isEmpty { current?.players = players }
        case "control":
            guard let type = attributes["type"], !type.isEmpty else { break }
            if attributes["required"] == "true" { requiredControls.append(type) } else { optionalControls.append(type) }
        case "rating":
            if let type = attributes["type"], let value = attributes["value"], !value.isEmpty {
                current?.rating = "\(type) \(value)"
            }
        case "wi-fi":
            if let players = attributes["players"], players != "0" { current?.onlinePlayers = players }
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(
        _ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "id": if gameID.isEmpty { gameID = value }
        case "title":
            if localeRank > bestTitleRank, !value.isEmpty {
                current?.title = value
                bestTitleRank = localeRank
            }
        case "synopsis":
            if localeRank > bestSynopsisRank, !value.isEmpty {
                current?.synopsis = value
                bestSynopsisRank = localeRank
            }
        case "developer": current?.developer = value
        case "publisher": current?.publisher = value
        case "genre": current?.genre = value
        case "region": current?.region = value
        case "languages": current?.languages = value
        case "game":
            current?.controls = (requiredControls + optionalControls).map(GameInfo.controllerName)
            if let current, !gameID.isEmpty { result[gameID] = current }
            current = nil
        default: break
        }
        text = ""
    }
}
