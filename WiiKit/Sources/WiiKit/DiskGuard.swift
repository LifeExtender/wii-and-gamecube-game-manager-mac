import Foundation

enum DiskPolicy: Sendable {
    case externalPhysicalOnly
    /// Used only by the test suite. Admits disk images and nothing else.
    case testingDiskImagesOnly
}

public enum DiskGuard {
    public static let maxFAT32Bytes: Int64 = 2 * 1024 * 1024 * 1024 * 1024

    /// Checked before anything is erased.
    public static func sizeRefusal(bytes: Int64, format: DriveFormat) -> String? {
        bytes > maxFAT32Bytes ? "This drive is larger than the 2 TB an MBR partition map can address." : nil
    }

    public static func isValidIdentifier(_ identifier: String) -> Bool {
        identifier.range(of: #"^disk[0-9]+(s[0-9]+)?$"#, options: .regularExpression) != nil
    }

    /// Turns anything typed into a name FAT32 accepts, so a bad name can't silently block formatting.
    public static func sanitizedVolumeName(_ raw: String) -> String {
        let allowed = raw.uppercased().replacingOccurrences(of: " ", with: "_").filter {
            ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_"
        }
        return String(allowed.prefix(11))
    }

    public static func isValidVolumeName(_ name: String) -> Bool {
        name.range(of: #"^[A-Z0-9_]{1,11}$"#, options: .regularExpression) != nil
    }

    /// Returns the reason this device must not be written to raw, or nil if it qualifies.
    static func refusal(
        for facts: DiskFacts, policy: DiskPolicy, externalPhysical: Set<String>, bootDisks: Set<String>
    ) -> String? {
        guard isValidIdentifier(facts.identifier) else { return "That is not a valid disk identifier." }
        switch policy {
        case .testingDiskImagesOnly:
            guard facts.busProtocol == "Disk Image", facts.virtualOrPhysical == "Virtual" else {
                return "Test policy only admits disk images."
            }
            return nil
        case .externalPhysicalOnly:
            guard !bootDisks.isEmpty else { return "The startup disk could not be identified, so nothing is allowed." }
            if bootDisks.contains(facts.parentWholeDisk) { return "This is the startup disk." }
            if facts.isInternal { return "This is an internal drive." }
            if !facts.removableOrExternal { return "macOS does not report this as an external drive." }
            if facts.osInternal { return "This disk is reserved for macOS." }
            if facts.virtualOrPhysical == "Virtual" || facts.busProtocol == "Disk Image" {
                return "This is a virtual disk, not a physical drive."
            }
            if !externalPhysical.contains(facts.parentWholeDisk) {
                return "macOS does not list this among its external physical disks."
            }
            return nil
        }
    }
}

public enum DriveFormat: String, CaseIterable, Identifiable, Sendable {
    case fat32, wbfs
    public var id: String { rawValue }
}
