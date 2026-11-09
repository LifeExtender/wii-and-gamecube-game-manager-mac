import Foundation

public struct DiscFile: Sendable, Equatable {
    public let path: String
    public let sizeBytes: Int64
}

public struct DiscFileNode: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let sizeBytes: Int64
    public let children: [DiscFileNode]?

    public var fileCount: Int { children?.reduce(0) { $0 + $1.fileCount } ?? 1 }
}

public enum DiscFiles {
    /// Keeps the game's own files and leaves out structures `wit` synthesises for its listing.
    public static func parse(listing: String) -> [DiscFile] {
        var files: [DiscFile] = []
        for rawLine in listing.split(whereSeparator: \.isNewline) {
            let fields = rawLine.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, !fields[2].hasPrefix("N="), let size = Int64(fields[2]) else { continue }
            let path = String(fields[3]).trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("files/") || path.hasPrefix("sys/") else { continue }
            files.append(DiscFile(path: path, sizeBytes: size))
        }
        return files
    }

    public static func folderCount(_ files: [DiscFile]) -> Int {
        var folders = Set<String>()
        for file in files {
            var parts = file.path.split(separator: "/").dropLast()
            while !parts.isEmpty {
                folders.insert(parts.joined(separator: "/"))
                parts = parts.dropLast()
            }
        }
        return folders.count
    }

    public static func tree(_ files: [DiscFile]) -> [DiscFileNode] {
        final class Folder {
            var folders: [String: Folder] = [:]
            var files: [(String, Int64, String)] = []
        }
        let root = Folder()
        for file in files {
            let parts = file.path.split(separator: "/").map(String.init)
            guard let name = parts.last else { continue }
            var folder = root
            for part in parts.dropLast() {
                if folder.folders[part] == nil { folder.folders[part] = Folder() }
                folder = folder.folders[part]!
            }
            folder.files.append((name, file.sizeBytes, file.path))
        }
        func build(_ folder: Folder, prefix: String) -> [DiscFileNode] {
            let directories = folder.folders.map { name, child -> DiscFileNode in
                let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                let children = build(child, prefix: path)
                return DiscFileNode(path: path, name: name, sizeBytes: children.reduce(0) { $0 + $1.sizeBytes }, children: children)
            }
            let leaves = folder.files.map { DiscFileNode(path: $0.2, name: $0.0, sizeBytes: $0.1, children: nil) }
            let byName: (DiscFileNode, DiscFileNode) -> Bool = {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return directories.sorted(by: byName) + leaves.sorted(by: byName)
        }
        return build(root, prefix: "")
    }
}
