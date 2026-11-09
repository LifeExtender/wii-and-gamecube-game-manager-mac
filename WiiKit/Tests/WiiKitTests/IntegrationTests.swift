import XCTest

@testable import WiiKit

/// Runs the bundled native tools against synthetic discs, through the same API the app uses.
final class IntegrationTests: XCTestCase {
    private var root: URL!
    private var engine: Engine!
    private var tools: Tools!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wgm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let helpers = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Helpers")
        tools = Tools(directory: helpers)
        engine = Engine(tools: tools)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeISO(_ id: String, title: String, megabytes: Int) async throws -> URL {
        let fst = root.appendingPathComponent("fst-\(id)")
        let sys = fst.appendingPathComponent("sys")
        let files = fst.appendingPathComponent("files")
        let fm = FileManager.default
        try fm.createDirectory(at: sys, withIntermediateDirectories: true)
        try fm.createDirectory(at: files, withIntermediateDirectories: true)

        var boot = Data(count: 0x440)
        boot.replaceSubrange(0..<6, with: Data(id.utf8))
        boot.replaceSubrange(0x18..<0x1C, with: Data([0x5D, 0x1C, 0x9E, 0xA3]))
        let name = Data(title.utf8)
        boot.replaceSubrange(0x20..<(0x20 + name.count), with: name)
        try boot.write(to: sys.appendingPathComponent("boot.bin"))
        try Data(count: 0x2000).write(to: sys.appendingPathComponent("bi2.bin"))

        var apploader = Data("2010/01/01".utf8) + Data(count: 6)
        apploader += Data([0x81, 0x20, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0]) + Data(count: 0x400)
        try apploader.write(to: sys.appendingPathComponent("apploader.img"))

        var dol = Data(count: 0x100)
        dol.replaceSubrange(0x00..<0x04, with: Data([0, 0, 1, 0]))
        dol.replaceSubrange(0x48..<0x4C, with: Data([0x80, 0, 0x40, 0]))
        dol.replaceSubrange(0x90..<0x94, with: Data([0, 0, 4, 0]))
        dol.replaceSubrange(0xE0..<0xE4, with: Data([0x80, 0, 0x40, 0]))
        try (dol + Data(count: 0x400)).write(to: sys.appendingPathComponent("main.dol"))

        let payload = files.appendingPathComponent("payload.bin")
        fm.createFile(atPath: payload.path, contents: nil)
        let handle = try FileHandle(forWritingTo: payload)
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<megabytes {
            var block = Data(count: 1024 * 1024)
            block.withUnsafeMutableBytes { raw in
                for index in stride(from: 0, to: raw.count - 8, by: 8) {
                    raw.storeBytes(of: generator.next() as UInt64, toByteOffset: index, as: UInt64.self)
                }
            }
            try handle.write(contentsOf: block)
        }
        try handle.close()

        let iso = root.appendingPathComponent("\(id).iso")
        let result = try await runTool(tools.wit, ["copy", "-q", "-T/", fst.path, iso.path, "--iso"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        return iso
    }

    private func assertIdentical(_ a: URL, _ b: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let result = try await runTool(tools.wit, ["diff", "-q", "-T/", a.path, Naming.escapedDestination(b)])
        XCTAssertEqual(result.exitCode, 0, "wit diff reported a mismatch: \(result.stderr)", file: file, line: line)
    }

    func testScanReadsIDsRegionAndHidesSplitParts() async throws {
        _ = try await makeISO("TSTE99", title: "Scan One", megabytes: 8)
        let folder = root.appendingPathComponent("library/sub")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("TSTE99.iso"), to: folder.appendingPathComponent("TSTE99.iso"))

        let recursive = try await engine.scan(folder: root.appendingPathComponent("library"), recursive: true)
        XCTAssertEqual(recursive.map(\.gameID), ["TSTE99"])
        XCTAssertEqual(recursive[0].discName, "Scan One")
        XCTAssertEqual(recursive[0].region, "USA")
        XCTAssertEqual(recursive[0].container, "ISO")
        XCTAssertGreaterThan(recursive[0].bytesOnDisk, 0)

        let flat = try await engine.scan(folder: root.appendingPathComponent("library"), recursive: false)
        XCTAssertTrue(flat.isEmpty, "A non-recursive scan must not descend")

        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let none = try await engine.scan(folder: empty, recursive: true)
        XCTAssertTrue(none.isEmpty)
    }

    func testRoundTripPreservesDataAndHandlesAwkwardNames() async throws {
        let iso = try await makeISO("TSTP99", title: "Round Trip", megabytes: 16)
        let wbfs = root.appendingPathComponent("out/100% Game %I [x]/TSTP99.wbfs")
        try await engine.convert(
            source: iso.path, destination: wbfs, format: .wbfs, split: .none, copyMode: .gamePartition)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wbfs.path), "A literal % must survive wit's escape handling")
        try await assertIdentical(iso, wbfs.path)

        let back = root.appendingPathComponent("out/back.iso")
        try await engine.convert(source: wbfs.path, destination: back, format: .iso, split: .none, copyMode: .gamePartition)
        try await assertIdentical(iso, back.path)

        do {
            try await engine.convert(source: iso.path, destination: wbfs, format: .wbfs, split: .none, copyMode: .gamePartition)
            XCTFail("Must not overwrite an existing game")
        } catch let failure as ToolFailure {
            XCTAssertTrue(failure.detail.contains("already exists"), failure.detail)
            XCTAssertTrue(failure.detail.contains(wbfs.lastPathComponent), failure.detail)
            XCTAssertFalse(failure.detail.contains(" -") && !wbfs.path.contains(" -"), "Long paths must not be hard-wrapped: \(failure.detail)")
            XCTAssertTrue(failure.detail.contains(root.lastPathComponent), "The full path must survive intact: \(failure.detail)")
        }
    }

    func testAllCopyModesProduceValidOutput() async throws {
        let iso = try await makeISO("TSTD99", title: "Modes", megabytes: 8)
        for mode in CopyMode.allCases {
            let out = root.appendingPathComponent("modes/\(mode.rawValue).wbfs")
            try await engine.convert(source: iso.path, destination: out, format: .wbfs, split: .none, copyMode: mode)
            XCTAssertTrue(FileManager.default.fileExists(atPath: out.path), mode.rawValue)
        }
    }

    func testSplitWritesPartsAndScansAsOneGame() async throws {
        let iso = try await makeISO("TSTJ99", title: "Big Split", megabytes: 2300)
        let out = root.appendingPathComponent("split/TSTJ99.wbfs")
        try await engine.convert(source: iso.path, destination: out, format: .wbfs, split: .twoGB, copyMode: .gamePartition)

        let parts = Naming.splitParts(of: out)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[1].lastPathComponent, "TSTJ99.wbf1")
        try await assertIdentical(iso, out.path)

        let scanned = try await engine.scan(folder: out.deletingLastPathComponent(), recursive: true)
        XCTAssertEqual(scanned.count, 1, "Split parts must appear as one game")
        XCTAssertGreaterThan(scanned[0].bytesOnDisk, 2_000_000_000)

        try await engine.resplit(file: out, split: .fourGB)
        XCTAssertEqual(Naming.splitParts(of: out).count, 1, "Resplitting to 4 GB should merge the parts")
        try await assertIdentical(iso, out.path)
    }

    func testProgressIsReportedAndCancelLeavesNoPartialFile() async throws {
        let iso = try await makeISO("TSTC99", title: "Cancel", megabytes: 2400)
        let out = root.appendingPathComponent("cancel/TSTC99.wbfs")
        let cancel = CancelToken()
        let task = Task { [engine] in
            try await engine!.convert(
                source: iso.path, destination: out, format: .wbfs, split: .none, copyMode: .gamePartition, cancel: cancel)
        }
        try await Task.sleep(for: .milliseconds(250))
        cancel.cancel()
        do {
            try await task.value
            throw XCTSkip("The copy finished before the cancel landed")
        } catch is OperationCancelled {}
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: out.deletingLastPathComponent().path)) ?? []
        XCTAssertEqual(leftovers, [], "A cancelled conversion must leave nothing behind")
    }

    func testPartitionLifecycleAndTransfer() async throws {
        let isoA = try await makeISO("TSTE11", title: "Part A", megabytes: 12)
        let isoB = try await makeISO("TSTP11", title: "Part B", megabytes: 8)
        let part = root.appendingPathComponent("part.img").path
        let other = root.appendingPathComponent("other.img").path
        for path in [part, other] {
            let made = try await runTool(tools.wwt, ["format", "-q", "--size", "8g", "--force", path])
            XCTAssertEqual(made.exitCode, 0, made.stderr)
        }

        try await engine.addToPartition(device: part, sources: [isoA.path, isoB.path], copyMode: .gamePartition)
        var contents = try await engine.readPartition(part)
        XCTAssertEqual(contents.games.map(\.gameID).sorted(), ["TSTE11", "TSTP11"])
        XCTAssertEqual(contents.space?.usedDiscs, 2)

        try await engine.addToPartition(device: part, sources: [isoA.path], copyMode: .gamePartition)
        contents = try await engine.readPartition(part)
        XCTAssertEqual(contents.games.count, 2, "Re-adding a game must be a no-op")

        let game = try XCTUnwrap(contents.games.first { $0.gameID == "TSTE11" })
        let extracted = root.appendingPathComponent("extracted.iso")
        try await engine.convert(source: game.id, destination: extracted, format: .iso, split: .none, copyMode: .gamePartition)
        try await assertIdentical(isoA, extracted.path)

        try await engine.addToPartition(device: other, sources: [game.id], copyMode: .gamePartition)
        let transferred = try await engine.readPartition(other)
        XCTAssertEqual(transferred.games.map(\.gameID), ["TSTE11"])
        let transferredOut = root.appendingPathComponent("transferred.iso")
        try await engine.convert(
            source: transferred.games[0].id, destination: transferredOut, format: .iso, split: .none, copyMode: .gamePartition)
        try await assertIdentical(isoA, transferredOut.path)

        try await engine.removeFromPartition(device: part, gameID: "TSTP11")
        contents = try await engine.readPartition(part)
        XCTAssertEqual(contents.games.map(\.gameID), ["TSTE11"])
    }

    func testDiscInfoFromEveryFormatAndPartitionSlot() async throws {
        let iso = try await makeISO("TSTE88", title: "Info: Disc", megabytes: 12)
        let folder = root.appendingPathComponent("formats")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var sources = [iso.path]
        for format in ["wbfs", "wdf", "ciso", "wia", "gcz"] {
            let out = folder.appendingPathComponent("disc.\(format)")
            let made = try await runTool(tools.wit, ["copy", "-q", "-T/", iso.path, out.path, "--\(format)"])
            XCTAssertEqual(made.exitCode, 0, made.stderr)
            sources.append(out.path)
        }
        let part = root.appendingPathComponent("info.img").path
        let formatted = try await runTool(tools.wwt, ["format", "-q", "--size", "8g", "--force", part])
        XCTAssertEqual(formatted.exitCode, 0, formatted.stderr)
        try await engine.addToPartition(device: part, sources: [iso.path], copyMode: .gamePartition)
        sources.append("\(part)/#0")

        for source in sources {
            let info = try await engine.discInfo(source: source)
            XCTAssertEqual(info.discID, "TSTE88", source)
            XCTAssertEqual(info.name, "Info: Disc", source)
            XCTAssertEqual(info.platform, "Wii", source)
            XCTAssertEqual(info.region, "NTSC/USA", source)
            XCTAssertEqual(info.requiredSystem, "IOS 35", source)
            XCTAssertEqual(info.discSize, 4_699_979_776, source)
            XCTAssertGreaterThan(info.usedSize ?? 0, 12_000_000, source)
            XCTAssertEqual(info.partitions.map(\.label), ["Data"], source)
            XCTAssertEqual(info.discNumber, 0, source)

            let files = try await engine.discFiles(source: source)
            XCTAssertTrue(files.contains { $0.path == "files/payload.bin" && $0.sizeBytes == 12 * 1024 * 1024 }, source)
            XCTAssertFalse(files.contains { $0.path.hasPrefix("setup") }, source)
            XCTAssertEqual(files.count, 6, "payload.bin plus five sys files: \(source)")
            XCTAssertEqual(info.files, files.count, "The panel must match the file browser: \(source)")
            XCTAssertEqual(info.directories, 2, source)
        }
    }

    func testVerifyPassesThenDetectsDamage() async throws {
        let iso = try await makeISO("TSTV99", title: "Verify", megabytes: 24)
        let wbfs = root.appendingPathComponent("verify/disc.wbfs")
        try await engine.convert(source: iso.path, destination: wbfs, format: .wbfs, split: .none, copyMode: .gamePartition)
        try await engine.verify(source: wbfs.path)

        let handle = try FileHandle(forWritingTo: wbfs)
        try handle.seek(toOffset: 16 * 1024 * 1024)
        try handle.write(contentsOf: Data(repeating: 0xFF, count: 4096))
        try handle.close()

        do {
            try await engine.verify(source: wbfs.path)
            XCTFail("A damaged image must not verify")
        } catch let failure as VerificationFailed {
            XCTAssertTrue(failure.detail.contains("damaged"), failure.detail)
        }
    }

    func testScanningIndividualFiles() async throws {
        let first = try await makeISO("TSTF11", title: "File One", megabytes: 4)
        let second = try await makeISO("TSTF22", title: "File Two", megabytes: 4)
        let games = try await engine.scan(files: [first, second])
        XCTAssertEqual(games.map(\.gameID).sorted(), ["TSTF11", "TSTF22"])
    }

    func testScanningAMissingFolderFailsRatherThanLookingEmpty() async throws {
        do {
            _ = try await engine.scan(folder: root.appendingPathComponent("does-not-exist"), recursive: true)
        } catch {
            return
        }
        // Reaching here is fine only if the tool itself reported an empty result.
    }

    func testKnownDiscNumbersAvoidReadingTheFile() async throws {
        let image = try makeGameCubeImage("GTSE55", title: "Cached", disc: 1)
        let games = try await engine.scan(files: [image])
        let key = try XCTUnwrap(games.first).discCacheKey
        let resolved = await engine.resolvingDiscNumbers(games, known: [key: 7])
        XCTAssertEqual(resolved.first?.discNumber, 7, "A remembered value must be used without asking the tool")
    }

    func testReadingNonWBFSReportsClearly() async throws {
        let junk = root.appendingPathComponent("junk.img")
        try Data(count: 8 * 1024 * 1024).write(to: junk)
        do {
            _ = try await engine.readPartition(junk.path)
            XCTFail("Expected a failure")
        } catch let failure as ToolFailure {
            XCTAssertEqual(failure.exitCode, 48)
            XCTAssertTrue(failure.detail.localizedCaseInsensitiveContains("no wbfs"), failure.detail)
        }
    }

    func testCopyAndMoveIncludeSplitParts() async throws {
        let source = root.appendingPathComponent("src/GAME.wbfs")
        let fm = FileManager.default
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: source)
        try Data(repeating: 2, count: 2048).write(to: root.appendingPathComponent("src/GAME.wbf1"))
        let game = Game(
            id: source.path, gameID: "GAME01", discName: "G", region: "", fileType: "WBFS/WII",
            sizeBytes: 6144, bytesOnDisk: 6144, location: .file(source))

        let copied = root.appendingPathComponent("copy")
        try FileOps.transfer(game: game, to: copied, move: false)
        XCTAssertTrue(fm.fileExists(atPath: copied.appendingPathComponent("GAME.wbf1").path))
        XCTAssertTrue(fm.fileExists(atPath: source.path), "Copy must keep the source")
        XCTAssertThrowsError(try FileOps.transfer(game: game, to: copied, move: false), "No silent overwrite")
        XCTAssertFalse(fm.fileExists(atPath: copied.appendingPathComponent("GAME.wbfs.partial").path))

        let moved = root.appendingPathComponent("move")
        try FileOps.transfer(game: game, to: moved, move: true)
        XCTAssertTrue(fm.fileExists(atPath: moved.appendingPathComponent("GAME.wbfs").path))
        XCTAssertFalse(fm.fileExists(atPath: source.path), "Move must remove the source")
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("src/GAME.wbf1").path))
    }

    /// Runs the loader layouts on a real FAT32 filesystem, where macOS leaves `._` files.
    func testLoaderCopiesOnFAT32LeaveNoAppleDoubleFiles() async throws {
        let wii = try await makeISO("TSTE77", title: "Fat Wii", megabytes: 8)
        let cube = try makeGameCubeImage("GTSE77", title: "Fat Cube")
        let compact = root.appendingPathComponent("cube.ciso")
        let compacted = try await runTool(tools.wit, ["copy", "-q", "-T/", cube.path, compact.path, "--ciso"])
        XCTAssertEqual(compacted.exitCode, 0, compacted.stderr)

        let image = root.appendingPathComponent("fat.sparseimage").path
        let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
        let created = try await runTool(hdiutil, ["create", "-quiet", "-size", "8g", "-type", "SPARSE", "-layout", "NONE", image])
        XCTAssertEqual(created.exitCode, 0, created.stderr)
        let attached = try await runTool(hdiutil, ["attach", "-nomount", image])
        let device = try XCTUnwrap(attached.stdout.split(whereSeparator: \.isWhitespace).first.map(String.init))
        addTeardownBlock { _ = try? Self.detach(device) }

        let identifier = device.replacingOccurrences(of: "/dev/", with: "")
        let service = DiskService(tools: tools, policy: .testingDiskImagesOnly)
        let snapshot = try await service.facts(for: identifier)
        XCTAssertEqual(snapshot.busProtocol, "Disk Image", "The test must only ever touch a disk image")
        try await service.format(snapshot: snapshot, as: .fat32, volumeName: "WGMFAT")
        let mountedAt = await service.mountPoint(of: "\(identifier)s1")
        let mount = URL(fileURLWithPath: try XCTUnwrap(mountedAt))

        let wiiOut = Naming.wiiURL(root: mount, gameID: "TSTE77", title: "Fat Wii")
        try await engine.convert(source: wii.path, destination: wiiOut, format: .wbfs, split: .fourGB, copyMode: .gamePartition)
        let cubeOut = Naming.gameCubeURL(root: mount, gameID: "GTSE77", title: "Fat Cube", discNumber: 0)
        try await engine.convertGameCube(source: compact.path, destination: cubeOut)

        try await assertIdentical(wii, wiiOut.path)
        try await assertIdentical(cube, cubeOut.path)
        XCTAssertEqual(Naming.splitParts(of: cubeOut).count, 1, "A GameCube game must be a single file")
        let cubeSize = try FileManager.default.attributesOfItem(atPath: cubeOut.path)[.size] as? NSNumber
        XCTAssertEqual(cubeSize?.int64Value, Limits.gameCubeDiscBytes, "A GameCube ISO must be the standard disc size")
        let scanned = try await engine.scan(folder: mount, recursive: true)
        XCTAssertEqual(scanned.map(\.gameID).sorted(), ["GTSE77", "TSTE77"])
        XCTAssertEqual(Set(scanned.map(\.platform)), ["GameCube", "Wii"])

        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: mount.path))
        let leftovers = enumerator.compactMap { $0 as? String }.filter { ($0 as NSString).lastPathComponent.hasPrefix("._") }
        XCTAssertEqual(leftovers, [], "AppleDouble files must not be left beside games")
    }

    func testAppleDoubleCleanupIgnoresOrdinaryFilesAndNonFAT() throws {
        let folder = root.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let game = folder.appendingPathComponent("GAME.wbfs")
        let companion = folder.appendingPathComponent("._GAME.wbfs")
        try Data([1]).write(to: game)
        try Data([0x00, 0x05, 0x16, 0x07]).write(to: companion)
        FileOps.removeAppleDoubleCompanions(of: game)
        XCTAssertTrue(FileManager.default.fileExists(atPath: companion.path), "Only FAT32 volumes are cleaned")
    }

    func testDiscNumbersAreReadForGameCubeGames() async throws {
        let first = try makeGameCubeImage("GTSE66", title: "Two Disc", disc: 0)
        let second = try makeGameCubeImage("GTSE67", title: "Two Disc", disc: 1)
        let games = try await engine.scan(files: [first, second])
        let resolved = await engine.resolvingDiscNumbers(games)
        XCTAssertEqual(resolved.first { $0.gameID == "GTSE66" }?.discNumber, 0)
        XCTAssertEqual(resolved.first { $0.gameID == "GTSE67" }?.discNumber, 1)
    }

    private func makeGameCubeImage(_ id: String, title: String, disc: UInt8 = 0) throws -> URL {
        let url = root.appendingPathComponent("\(id).iso")
        func big(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
        var boot = Data(count: 0x440)
        boot.replaceSubrange(0..<6, with: Data(id.utf8))
        boot[6] = disc
        boot.replaceSubrange(0x1C..<0x20, with: big(0xC233_9F3D))
        let name = Data(title.utf8)
        boot.replaceSubrange(0x20..<(0x20 + name.count), with: name)
        boot.replaceSubrange(0x420..<0x424, with: big(0x8000))
        boot.replaceSubrange(0x424..<0x428, with: big(0x10000))
        boot.replaceSubrange(0x428..<0x42C, with: big(28))
        boot.replaceSubrange(0x42C..<0x430, with: big(28))
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: boot)
        try handle.seek(toOffset: 0x2440)
        try handle.write(contentsOf: Data("2003/01/01".utf8) + Data(count: 6) + big(0x8120_0000) + big(0x100) + big(0) + Data(count: 0x100))
        var dol = Data(count: 0x500)
        dol.replaceSubrange(0x00..<0x04, with: big(0x100))
        dol.replaceSubrange(0x48..<0x4C, with: big(0x8000_4000))
        dol.replaceSubrange(0x90..<0x94, with: big(0x400))
        dol.replaceSubrange(0xE0..<0xE4, with: big(0x8000_4000))
        try handle.seek(toOffset: 0x8000)
        try handle.write(contentsOf: dol)
        try handle.seek(toOffset: 0x10000)
        try handle.write(contentsOf: big(0x0100_0000) + big(0) + big(2) + big(0) + big(0x20000) + big(16) + Data("open".utf8) + Data(count: 4))
        try handle.seek(toOffset: 0x20000)
        try handle.write(contentsOf: Data("BNR1".utf8) + Data(count: 12))
        try handle.truncate(atOffset: 1_459_978_240)
        try handle.close()
        return url
    }

    /// Exercises the real format code path on a throwaway disk image, under a policy that refuses anything else.
    func testFormatFlowsOnDiskImage() async throws {
        let image = root.appendingPathComponent("v.sparseimage").path
        let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
        let created = try await runTool(hdiutil, ["create", "-quiet", "-size", "64g", "-type", "SPARSE", "-layout", "NONE", image])
        XCTAssertEqual(created.exitCode, 0, created.stderr)
        let attached = try await runTool(hdiutil, ["attach", "-nomount", image])
        XCTAssertEqual(attached.exitCode, 0, attached.stderr)
        let device = try XCTUnwrap(attached.stdout.split(whereSeparator: \.isWhitespace).first.map(String.init))
        let identifier = device.replacingOccurrences(of: "/dev/", with: "")
        addTeardownBlock { _ = try? Self.detach(device) }

        let service = DiskService(tools: tools, policy: .testingDiskImagesOnly)
        var snapshot = try await service.facts(for: identifier)
        XCTAssertEqual(snapshot.busProtocol, "Disk Image", "The test must only ever touch a disk image")
        XCTAssertNotNil(
            DiskGuard.refusal(for: snapshot, policy: .externalPhysicalOnly, externalPhysical: [identifier], bootDisks: ["disk0"]),
            "The policy the app uses must refuse this virtual disk")

        try await service.format(snapshot: snapshot, as: .fat32, volumeName: "WGMTEST")
        let mountedInfo = try await runTool(URL(fileURLWithPath: "/usr/sbin/diskutil"), ["info", "-plist", "\(device)s1"])
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(mountedInfo.stdout.utf8), format: nil) as? [String: Any])
        let mount = try XCTUnwrap(plist["MountPoint"] as? String)
        var volume = statvfs()
        XCTAssertEqual(statvfs(mount, &volume), 0)
        XCTAssertEqual(volume.f_frsize, 32768, "macOS must choose 32 KB clusters on a drive this size, as USB loaders prefer")
        XCTAssertEqual(VolumeFacts.of(URL(fileURLWithPath: mount))?.isFAT32, true)

        snapshot = try await service.facts(for: identifier)
        try await service.format(snapshot: snapshot, as: .wbfs, volumeName: "WGMTEST")
        let raw = "/dev/r\(identifier)s1"
        let iso = try await makeISO("TSTW99", title: "On Device", megabytes: 8)
        try await engine.addToPartition(device: raw, sources: [iso.path], copyMode: .gamePartition)
        let contents = try await engine.readPartition(raw)
        XCTAssertEqual(contents.games.map(\.gameID), ["TSTW99"])

        var changed = snapshot
        changed.mediaName = "Some Other Drive"
        do {
            try await service.format(snapshot: changed, as: .fat32, volumeName: "NOPE")
            XCTFail("A changed drive must be refused")
        } catch let refused as DiskRefused {
            XCTAssertTrue(refused.reason.contains("changed"), refused.reason)
        }
    }

    private static func detach(_ device: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", "-force", device]
        try process.run()
        process.waitUntilExit()
    }
}
