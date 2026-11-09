import Foundation

/// Every operation that reads or writes a disc image, built on Wiimms ISO Tools.
public struct Engine: Sendable {
    public typealias Progress = @Sendable (ToolProgress) -> Void

    public let tools: Tools

    public init(tools: Tools) { self.tools = tools }

    /// Titles are the app's job, so the tools shouldn't search for their own lists.
    private static let noTitles = "-T/"

    /// Otherwise the tools hard-wrap messages at 80 columns, splitting paths in error text.
    private static let wideOutput = ["--width", "2000"]

    private func wit(_ arguments: [String]) async throws -> ToolResult {
        try await runTool(tools.wit, Self.wideOutput + arguments)
    }

    private func wwt(_ arguments: [String]) async throws -> ToolResult {
        try await runTool(tools.wwt, Self.wideOutput + arguments)
    }

    /// Runs a tool that changes something, turning an interrupted run into a cancellation.
    private func perform(_ tool: URL, _ arguments: [String], cancel: CancelToken?, progress: Progress?) async throws {
        let result = try await runTool(tool, Self.wideOutput + arguments, cancel: cancel, progress: progress)
        if result.exitCode == ToolOutput.interruptedExitCode || cancel?.isCancelled == true { throw OperationCancelled() }
        try result.requireSuccess()
    }

    // MARK: Scanning

    public func scan(folder: URL, recursive: Bool) async throws -> [Game] {
        try await scan((recursive ? ["-r"] : []) + [folder.path])
    }

    public func scan(files: [URL]) async throws -> [Game] {
        try await scan(files.map(\.path))
    }

    /// A folder with one unreadable file still reports the rest, so only a run with no listing fails.
    private func scan(_ targets: [String]) async throws -> [Game] {
        let result = try await wit(["ll", Self.noTitles, "--sections"] + targets)
        if !result.stdout.contains("[summary]") { try result.requireSuccess() }
        return Self.parseFileGames(result.stdout)
    }

    static func parseFileGames(_ output: String) -> [Game] {
        parseSections(output).compactMap { section in
            guard section.name.hasPrefix("disc-"), let id = section.values["id"], !id.isEmpty,
                let filename = section.values["filename"]
            else { return nil }
            let url = URL(fileURLWithPath: filename)
            let onDisk = Naming.splitParts(of: url).reduce(Int64(0)) { total, part in
                let size = (try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.int64Value
                return total + (size ?? 0)
            }
            return Game(
                id: section.values["source"] ?? filename,
                gameID: id,
                discName: section.values["name"] ?? id,
                region: section.values["region"] ?? "",
                fileType: section.values["filetype"] ?? "",
                sizeBytes: Int64(section.values["size"] ?? "") ?? 0,
                bytesOnDisk: onDisk,
                location: .file(url))
        }
    }

    public func readPartition(_ device: String) async throws -> PartitionContents {
        let result = try await wwt(["ll", Self.noTitles, "-p", device, "--sections"]).requireSuccess()
        return Self.parsePartition(result.stdout, device: device)
    }

    static func parsePartition(_ output: String, device: String) -> PartitionContents {
        let sections = parseSections(output)
        var space: PartitionSpace?
        if let info = sections.first(where: { $0.name.hasPrefix("wbfs-") })?.values {
            space = PartitionSpace(
                usedMiB: Int64(info["used_mib"] ?? "") ?? 0,
                freeMiB: Int64(info["free_mib"] ?? "") ?? 0,
                totalMiB: Int64(info["total_mib"] ?? "") ?? 0,
                usedDiscs: Int(info["used_discs"] ?? "") ?? 0,
                totalDiscs: Int(info["total_discs"] ?? "") ?? 0)
        }
        let games: [Game] = sections.compactMap { section in
            guard section.name.hasPrefix("disc-"), let id = section.values["id"], !id.isEmpty,
                let slotText = section.values["wbfs_slot"], let slot = Int(slotText)
            else { return nil }
            let size = Int64(section.values["size"] ?? "") ?? 0
            return Game(
                id: section.values["source"] ?? "\(device)/#\(slot)",
                gameID: id,
                discName: section.values["name"] ?? id,
                region: section.values["region"] ?? "",
                fileType: section.values["filetype"] ?? "WBFS/WII",
                sizeBytes: size,
                bytesOnDisk: size,
                location: .partition(device: device, slot: slot))
        }
        return PartitionContents(games: games, space: space)
    }

    // MARK: Inspecting one disc

    public func discInfo(source: String) async throws -> DiscInfo {
        let dump = try await wit(["dump", Self.noTitles, source]).requireSuccess()
        var info = DiscInfo.parse(dump: dump.stdout)
        let identity = try await wit(["id8", Self.noTitles, source])
        if identity.exitCode == 0 { info.applyID8(identity.stdout) }
        // The dump's own counts include structures the tool synthesises, so use the game's real files.
        if let listing = try? await discFiles(source: source), !listing.isEmpty {
            info.files = listing.count
            info.directories = DiscFiles.folderCount(listing)
        }
        return info
    }

    public func discFiles(source: String) async throws -> [DiscFile] {
        let result = try await wit(["files", Self.noTitles, "--long", "--long", "--psel", "data", "--pmode", "none", source])
            .requireSuccess()
        return DiscFiles.parse(listing: result.stdout)
    }

    /// The zero-based disc number, which distinguishes the discs of a multi-disc game.
    public func discNumber(source: String) async throws -> Int {
        var info = DiscInfo()
        info.applyID8(try await wit(["id8", Self.noTitles, source]).stdout)
        return info.discNumber ?? 0
    }

    /// Fills in disc numbers for GameCube games, which the scan doesn't report. Without them the
    /// second disc of a game looks like a duplicate of the first. `known` avoids reading them again.
    public func resolvingDiscNumbers(_ games: [Game], known: [String: Int] = [:]) async -> [Game] {
        var resolved = games
        for index in resolved.indices where resolved[index].platform == "GameCube" {
            if let number = known[resolved[index].discCacheKey] {
                resolved[index].discNumber = number
            } else if let number = try? await discNumber(source: resolved[index].id) {
                resolved[index].discNumber = number
            }
        }
        return resolved
    }

    /// Checks the disc's hashes. `--limit` stops at the first few errors rather than listing thousands.
    public func verify(source: String, cancel: CancelToken? = nil, progress: Progress? = nil) async throws {
        let arguments = Self.wideOutput + ["verify", Self.noTitles, "--limit", "5", "--progress", source]
        let result = try await runTool(tools.wit, arguments, cancel: cancel, progress: progress)
        if result.exitCode == ToolOutput.interruptedExitCode || cancel?.isCancelled == true { throw OperationCancelled() }
        guard result.exitCode != 0 else { return }
        if result.stdout.contains("-ERR") || result.stderr.contains("-ERR") {
            throw VerificationFailed(detail: "The disc's hashes do not match, so this image is damaged.")
        }
        throw VerificationFailed(detail: ToolOutput.failureDetail(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode))
    }

    /// The sizes each disc would actually occupy once scrubbed, keyed by source.
    public func scrubbedSizes(sources: [String]) async throws -> [String: Int64] {
        guard !sources.isEmpty else { return [:] }
        return Self.parseScrubbedSizes(try await wit(["isosize", Self.noTitles, "--long"] + sources).stdout)
    }

    static func parseScrubbedSizes(_ output: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let blocks = Int64(fields[0]), Int64(fields[1]) != nil else { continue }
            let source = String(fields[2]).trimmingCharacters(in: .whitespaces)
            let bytes = blocks * 32 * 1024
            sizes[source] = bytes
            if let slot = source.range(of: #"/#[0-9]+$"#, options: .regularExpression) {
                sizes[String(source[..<slot.lowerBound])] = bytes
            }
        }
        return sizes
    }

    // MARK: Writing

    /// A FAT32 volume cannot hold a file of 4 GiB or more, so an unsplit request is raised to a
    /// 4 GB split. The split only takes effect when the output would actually exceed it.
    static func effectiveSplit(_ requested: SplitMode, destination: URL) -> SplitMode {
        guard requested == .none, VolumeFacts.of(destination)?.isFAT32 == true else { return requested }
        return .fourGB
    }

    public func convert(
        source: String, destination: URL, format: OutputFormat, split: SplitMode, copyMode: CopyMode,
        cancel: CancelToken? = nil, progress: Progress? = nil
    ) async throws {
        try makeParentFolder(of: destination)
        let split = Self.effectiveSplit(split, destination: destination)
        let arguments = ["copy", Self.noTitles, source, Naming.escapedDestination(destination.path), format.flag]
            + split.arguments + copyMode.arguments + ["--progress"]
        try await perform(tools.wit, arguments, cancel: cancel, progress: progress)
        FileOps.removeAppleDoubleCompanions(of: destination)
    }

    /// Writes a GameCube disc as one ISO of the standard size. CISO files don't record a disc size,
    /// so the tool assumes a 4.7 GB Wii disc and would otherwise pad the game out to that, and FAT32
    /// would then split it. Truncation can stop a few bytes short, which the tool itself rejects.
    public func convertGameCube(
        source: String, destination: URL, cancel: CancelToken? = nil, progress: Progress? = nil
    ) async throws {
        try makeParentFolder(of: destination)
        let arguments = [
            "copy", Self.noTitles, source, Naming.escapedDestination(destination.path), "--iso", "--trunc", "--psel", "all", "--progress",
        ]
        try await perform(tools.wit, arguments, cancel: cancel, progress: progress)
        let size = (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        if size < Limits.gameCubeDiscBytes {
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(Limits.gameCubeDiscBytes))
        }
        FileOps.removeAppleDoubleCompanions(of: destination)
    }

    public func resplit(file: URL, split: SplitMode, cancel: CancelToken? = nil, progress: Progress? = nil) async throws {
        let splitting = split.arguments.isEmpty ? ["--no-split"] : split.arguments
        try await perform(tools.wit, ["convert", Self.noTitles, file.path] + splitting + ["--progress"], cancel: cancel, progress: progress)
    }

    /// `--update` makes re-adding an existing game a harmless no-op.
    public func addToPartition(
        device: String, sources: [String], copyMode: CopyMode, cancel: CancelToken? = nil, progress: Progress? = nil
    ) async throws {
        let arguments = ["add", Self.noTitles, "-p", device, "--update"] + sources + copyMode.arguments + ["--progress"]
        try await perform(tools.wwt, arguments, cancel: cancel, progress: progress)
    }

    public func removeFromPartition(device: String, gameID: String) async throws {
        try await perform(tools.wwt, ["remove", Self.noTitles, "-p", device, gameID], cancel: nil, progress: nil)
    }

    private func makeParentFolder(of file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}
