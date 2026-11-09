import Foundation

public struct DiskFacts: Equatable, Sendable, Identifiable {
    public var id: String { identifier }
    public var identifier: String
    public var parentWholeDisk: String
    public var mediaName: String
    public var sizeBytes: Int64
    public var isWholeDisk: Bool
    public var isInternal: Bool
    public var removableOrExternal: Bool
    public var osInternal: Bool
    public var virtualOrPhysical: String
    public var busProtocol: String

    public init(
        identifier: String, parentWholeDisk: String, mediaName: String, sizeBytes: Int64,
        isWholeDisk: Bool, isInternal: Bool, removableOrExternal: Bool, osInternal: Bool,
        virtualOrPhysical: String, busProtocol: String
    ) {
        self.identifier = identifier
        self.parentWholeDisk = parentWholeDisk
        self.mediaName = mediaName
        self.sizeBytes = sizeBytes
        self.isWholeDisk = isWholeDisk
        self.isInternal = isInternal
        self.removableOrExternal = removableOrExternal
        self.osInternal = osInternal
        self.virtualOrPhysical = virtualOrPhysical
        self.busProtocol = busProtocol
    }

    /// Missing safety keys read as the unsafe value, so an unexpected plist is refused.
    public init?(plist: [String: Any]) {
        guard let identifier = plist["DeviceIdentifier"] as? String else { return nil }
        self.identifier = identifier
        parentWholeDisk = plist["ParentWholeDisk"] as? String ?? identifier
        mediaName = plist["MediaName"] as? String ?? plist["IORegistryEntryName"] as? String ?? "Unknown"
        sizeBytes = (plist["Size"] as? NSNumber)?.int64Value ?? (plist["TotalSize"] as? NSNumber)?.int64Value ?? 0
        isWholeDisk = plist["WholeDisk"] as? Bool ?? false
        isInternal = plist["Internal"] as? Bool ?? true
        removableOrExternal = plist["RemovableMediaOrExternalDevice"] as? Bool ?? false
        osInternal = plist["OSInternalMedia"] as? Bool ?? true
        virtualOrPhysical = plist["VirtualOrPhysical"] as? String ?? "Virtual"
        busProtocol = plist["BusProtocol"] as? String ?? "Unknown"
    }

    /// Identifies the physical drive, to catch a disk number being reassigned after a replug.
    public func isSameDrive(as other: DiskFacts) -> Bool {
        identifier == other.identifier && mediaName == other.mediaName
            && sizeBytes == other.sizeBytes && busProtocol == other.busProtocol
    }
}

public struct DiskPartition: Identifiable, Sendable, Equatable {
    public var id: String { identifier }
    public let identifier: String
    public let sizeBytes: Int64
    public let content: String
    public let volumeName: String
    public let mountPoint: String?
    public let volumeUUID: String

    public init(identifier: String, sizeBytes: Int64, content: String, volumeName: String, mountPoint: String?, volumeUUID: String = "") {
        self.volumeUUID = volumeUUID
        self.identifier = identifier
        self.sizeBytes = sizeBytes
        self.content = content
        self.volumeName = volumeName
        self.mountPoint = mountPoint
    }
}

public struct ExternalDisk: Identifiable, Sendable, Equatable {
    public var id: String { facts.identifier }
    public let facts: DiskFacts
    public let partitions: [DiskPartition]
}
