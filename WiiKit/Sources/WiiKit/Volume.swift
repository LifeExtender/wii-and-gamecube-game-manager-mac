import Foundation

public struct VolumeFacts: Sendable {
    public let fileSystem: String
    public let availableBytes: Int64
    public var isFAT32: Bool { fileSystem == "msdos" }

    public static func of(_ url: URL) -> VolumeFacts? {
        var existing = url
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            existing.deleteLastPathComponent()
        }
        var info = statfs()
        guard statfs(existing.path, &info) == 0 else { return nil }
        let name = withUnsafePointer(to: &info.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        return VolumeFacts(fileSystem: name, availableBytes: Int64(info.f_bavail) * Int64(info.f_bsize))
    }
}

public enum Limits {
    public static let fat32MaxFileBytes: Int64 = 4 * 1024 * 1024 * 1024 - 1
    public static let gameCubeDiscBytes: Int64 = 1_459_978_240
}
