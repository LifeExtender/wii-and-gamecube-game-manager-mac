import Foundation

public struct DiskService: Sendable {
    private let tools: Tools
    private let policy: DiskPolicy

    public init(tools: Tools) {
        self.init(tools: tools, policy: .externalPhysicalOnly)
    }

    init(tools: Tools, policy: DiskPolicy) {
        self.tools = tools
        self.policy = policy
    }

    private static let diskutil = URL(fileURLWithPath: "/usr/sbin/diskutil")

    // MARK: Inspection

    private func plist(_ arguments: [String]) async throws -> [String: Any] {
        let result = try await runTool(Self.diskutil, arguments)
        guard result.exitCode == 0,
            let object = try? PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil),
            let dictionary = object as? [String: Any]
        else { throw DiskRefused("diskutil could not describe the disks.") }
        return dictionary
    }

    public func facts(for identifier: String) async throws -> DiskFacts {
        guard DiskGuard.isValidIdentifier(identifier) else { throw DiskRefused("Invalid disk identifier.") }
        guard let facts = DiskFacts(plist: try await plist(["info", "-plist", "/dev/\(identifier)"])) else {
            throw DiskRefused("diskutil returned no details for \(identifier).")
        }
        return facts
    }

    public func mountPoint(of identifier: String) async -> String? {
        guard DiskGuard.isValidIdentifier(identifier),
            let info = try? await plist(["info", "-plist", "/dev/\(identifier)"]),
            let mount = info["MountPoint"] as? String, !mount.isEmpty
        else { return nil }
        return mount
    }

    /// Fails closed: an empty set makes the guard refuse everything.
    func bootDisks() async -> Set<String> {
        guard let info = try? await plist(["info", "-plist", "/"]) else { return [] }
        var disks = Set<String>()
        if let parent = info["ParentWholeDisk"] as? String { disks.insert(parent) }
        if let stores = info["APFSPhysicalStores"] as? [[String: Any]] {
            for store in stores {
                guard let name = store["APFSPhysicalStore"] as? String,
                    let match = name.range(of: #"^disk[0-9]+"#, options: .regularExpression)
                else { continue }
                disks.insert(String(name[match]))
            }
        }
        return disks
    }

    private func externalPhysicalDisks() async throws -> Set<String> {
        let list = try await plist(["list", "-plist", "external", "physical"])
        return Set(list["WholeDisks"] as? [String] ?? [])
    }

    func refusal(for facts: DiskFacts) async throws -> String? {
        DiskGuard.refusal(
            for: facts, policy: policy,
            externalPhysical: try await externalPhysicalDisks(), bootDisks: await bootDisks())
    }

    public func listExternal() async throws -> [ExternalDisk] {
        let list = try await plist(["list", "-plist", "external", "physical"])
        let entries = list["AllDisksAndPartitions"] as? [[String: Any]] ?? []
        var disks: [ExternalDisk] = []
        for entry in entries {
            guard let identifier = entry["DeviceIdentifier"] as? String else { continue }
            let facts = try await facts(for: identifier)
            guard try await refusal(for: facts) == nil else { continue }
            let partitions = (entry["Partitions"] as? [[String: Any]] ?? []).compactMap { part -> DiskPartition? in
                guard let id = part["DeviceIdentifier"] as? String else { return nil }
                return DiskPartition(
                    identifier: id,
                    sizeBytes: (part["Size"] as? NSNumber)?.int64Value ?? 0,
                    content: part["Content"] as? String ?? "",
                    volumeName: part["VolumeName"] as? String ?? "",
                    mountPoint: part["MountPoint"] as? String,
                    volumeUUID: part["VolumeUUID"] as? String ?? "")
            }
            disks.append(ExternalDisk(facts: facts, partitions: partitions))
        }
        return disks
    }

    // MARK: Raw access

    /// Gives this user the device nodes of one vetted external partition, via a single admin
    /// prompt. `wwt` then runs unprivileged. macOS recreates the nodes when the drive is unplugged.
    public func prepareRawAccess(identifier: String) async throws -> String {
        let facts = try await facts(for: identifier)
        if let reason = try await refusal(for: facts) { throw DiskRefused(reason) }
        let raw = "/dev/r\(identifier)"
        if access(raw, R_OK | W_OK) != 0 {
            try await runPrivileged("/usr/sbin/chown \(getuid()) /dev/\(identifier) \(raw)")
        }
        try Self.confirmRawDeviceOpens(raw)
        return raw
    }

    /// macOS can refuse raw device access even to root unless the app has Full Disk Access.
    private static func confirmRawDeviceOpens(_ path: String) throws {
        let descriptor = Darwin.open(path, O_RDONLY)
        if descriptor >= 0 {
            Darwin.close(descriptor)
            return
        }
        if errno == EPERM {
            throw DiskRefused("macOS blocked raw access to this drive. Add Wii Game Manager under System Settings > Privacy & Security > Full Disk Access, then try again.")
        }
    }

    public func eject(identifier: String) async throws {
        let whole = try await facts(for: identifier).parentWholeDisk
        let result = try await runTool(Self.diskutil, ["eject", "/dev/\(whole)"])
        guard result.exitCode == 0 else {
            throw DiskRefused("macOS could not eject the drive. Close anything using it and try again.")
        }
    }

    private func runPrivileged(_ shellCommand: String) async throws {
        let escaped = shellCommand.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let result = try await runTool(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
        guard result.exitCode == 0 else {
            if result.stderr.contains("-128") { throw OperationCancelled() }
            throw DiskRefused(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: Formatting

    /// Re-checks the drive immediately before erasing and refuses anything but the disk the user confirmed.
    public func format(
        snapshot: DiskFacts, as kind: DriveFormat, volumeName: String,
        status: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let current = try await facts(for: snapshot.identifier)
        guard current.isSameDrive(as: snapshot) else {
            throw DiskRefused("The drive at \(snapshot.identifier) has changed. Reopen this window and check again.")
        }
        guard current.isWholeDisk, current.identifier == current.parentWholeDisk else {
            throw DiskRefused("Only a whole drive can be formatted.")
        }
        if let reason = try await refusal(for: current) { throw DiskRefused(reason) }
        guard DiskGuard.isValidVolumeName(volumeName) else {
            throw DiskRefused("Use 1 to 11 capital letters, digits or underscores for the name.")
        }
        if let reason = DiskGuard.sizeRefusal(bytes: current.sizeBytes, format: kind) { throw DiskRefused(reason) }

        let disk = current.identifier
        // A raw WBFS format needs device access, so prove it's available before erasing anything.
        if kind == .wbfs { _ = try await prepareRawAccess(identifier: disk) }
        status?("Erasing the drive")
        let erase = try await runTool(
            Self.diskutil, ["eraseDisk", "MS-DOS FAT32", volumeName, "MBRFormat", "/dev/\(disk)"])
        guard erase.exitCode == 0 else {
            throw DiskRefused(erase.stderr.isEmpty ? erase.stdout : erase.stderr)
        }

        // diskutil already chooses 32 KB clusters for FAT32 drives over 32 GB.
        switch kind {
        case .fat32:
            break
        case .wbfs:
            status?("Writing the WBFS partition")
            _ = try await runTool(Self.diskutil, ["unmountDisk", "/dev/\(disk)"])
            let raw = try await prepareRawAccess(identifier: "\(disk)s1")
            try await runTool(tools.wwt, ["format", "--force", raw]).requireSuccess()
        }
    }
}
