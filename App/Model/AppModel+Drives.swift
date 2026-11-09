import Foundation
import WiiKit

extension AppModel {
    func refreshDrives() {
        Task { await refreshDrivesNow() }
    }

    func refreshDrivesNow() async {
        let found = (try? await disks.listExternal()) ?? []
        drives = found.flatMap(Self.entries)
        let present = Set(drives.map(\.identifier))
        for list in libraries {
            if let identifier = list.driveIdentifier, !present.contains(identifier) { remove(list) }
        }
        restoreMissingLibraries()
        openGameDrives()
    }

    /// Reads any mounted drive laid out for USB loaders, so it can be compared without a click.
    /// Other drives, such as camera cards, are left alone.
    private func openGameDrives() {
        for drive in drives where library(for: drive) == nil {
            guard let mount = drive.mountPoint else { continue }
            let root = URL(fileURLWithPath: mount)
            let isGameDrive = ["wbfs", "games"].contains {
                FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
            }
            if isGameDrive { open(drive, select: false) }
        }
    }

    /// Hides partitions that cannot hold games, such as EFI and Mac volumes.
    private static func entries(of disk: ExternalDisk) -> [DriveEntry] {
        if disk.partitions.isEmpty {
            return [
                DriveEntry(
                    identifier: disk.id, diskIdentifier: disk.id, name: disk.facts.mediaName,
                    sizeBytes: disk.facts.sizeBytes, mountPoint: nil, freeBytes: nil)
            ]
        }
        let excluded = ["EFI", "Microsoft Reserved"]
        return disk.partitions.filter { !$0.content.hasPrefix("Apple_") && !excluded.contains($0.content) }.map { partition in
            DriveEntry(
                identifier: partition.identifier, diskIdentifier: disk.id,
                name: partition.volumeName.isEmpty ? disk.facts.mediaName : partition.volumeName,
                sizeBytes: partition.sizeBytes, mountPoint: partition.mountPoint,
                freeBytes: partition.mountPoint.flatMap { VolumeFacts.of(URL(fileURLWithPath: $0))?.availableBytes },
                key: partition.volumeUUID)
        }
    }

    func library(for drive: DriveEntry) -> GameList? {
        libraries.first { $0.driveIdentifier == drive.identifier }
    }

    func open(_ drive: DriveEntry, select: Bool = true) {
        if let existing = library(for: drive) {
            if select { pane = .library(existing.id) }
            return
        }
        if let mount = drive.mountPoint {
            show(drive, source: .folder(URL(fileURLWithPath: mount)), select: select)
            return
        }
        let service = disks
        Task {
            do {
                let device = try await service.prepareRawAccess(identifier: drive.identifier)
                // The password prompt can outlast a second click on the same drive.
                guard library(for: drive) == nil else { return }
                show(drive, source: .partition(device: device, identifier: drive.identifier), select: true)
            } catch is OperationCancelled {
            } catch {
                notice = Notice(title: "Could Not Open Drive", message: error.localizedDescription)
            }
        }
    }

    private func show(_ drive: DriveEntry, source: ListSource, select: Bool) {
        let list = GameList(source: source, name: drive.name, driveIdentifier: drive.identifier)
        list.syncKey = drive.key.isEmpty ? nil : drive.key
        libraries.append(list)
        reload(list)
        if select { pane = .library(list.id) }
    }

    func eject(_ drive: DriveEntry) {
        let service = disks
        Task {
            do {
                try await service.eject(identifier: drive.identifier)
            } catch {
                notice = Notice(title: "Could Not Eject", message: error.localizedDescription)
            }
            refreshDrives()
        }
    }

    /// Free and total bytes for a drive's library, from the filesystem or the WBFS header.
    func capacity(of list: GameList) -> (free: Int64, total: Int64)? {
        if let space = list.space, space.totalMiB > 0 {
            return (space.freeMiB * 1_048_576, space.totalMiB * 1_048_576)
        }
        guard let identifier = list.driveIdentifier, let drive = drives.first(where: { $0.id == identifier }),
            let folder = list.source.folder, let volume = VolumeFacts.of(folder)
        else { return nil }
        return (volume.availableBytes, drive.sizeBytes)
    }

    func usedFraction(of drive: DriveEntry) -> Double? {
        if let list = library(for: drive), let capacity = capacity(of: list), capacity.total > 0 {
            return 1 - Double(capacity.free) / Double(capacity.total)
        }
        guard let free = drive.freeBytes, drive.sizeBytes > 0 else { return nil }
        return 1 - Double(free) / Double(drive.sizeBytes)
    }

    /// Game IDs present on connected drives, for the "on drive" marks.
    func gameIDsOnDrives(excluding list: GameList) -> Set<String> {
        Set(libraries.filter { $0 !== list && $0.isDrive }.flatMap { $0.games.map(\.gameID) })
    }

    /// Closes any open view of the drive, so a reformat can't leave a stale library behind.
    func forgetLibraries(onDisk disk: String) {
        for list in libraries where list.driveIdentifier?.hasPrefix(disk) == true { remove(list) }
    }

    /// Sets up a freshly formatted drive and opens it.
    func finishFormat(disk: String, kind: DriveFormat) async {
        let partition = "\(disk)s1"
        if kind == .fat32, let mount = await disks.mountPoint(of: partition) {
            for folder in ["wbfs", "games"] {
                let url = URL(fileURLWithPath: mount).appendingPathComponent(folder, isDirectory: true)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                FileOps.removeAppleDoubleCompanions(of: url)
            }
            var volume = statvfs()
            if statvfs(mount, &volume) == 0, volume.f_frsize < 32768 {
                notice = Notice(
                    title: "Formatted with \(volume.f_frsize / 1024) KB Clusters",
                    message: "macOS only uses the 32 KB clusters USB loaders prefer on drives over 32 GB. If a game won't load, try a larger drive.")
            }
        }
        await refreshDrivesNow()
        if let entry = drives.first(where: { $0.identifier == partition }) { open(entry) }
    }
}
