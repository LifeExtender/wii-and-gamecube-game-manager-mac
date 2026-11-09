import Foundation

public struct Tools: Sendable {
    public let wit: URL
    public let wwt: URL

    public init(directory: URL) {
        wit = directory.appendingPathComponent("wit")
        wwt = directory.appendingPathComponent("wwt")
    }
}

public struct ToolResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    /// Throws the tool's own error message if it did not succeed.
    @discardableResult
    func requireSuccess() throws -> ToolResult {
        guard exitCode != 0 else { return self }
        throw ToolFailure(exitCode: exitCode, detail: ToolOutput.failureDetail(stdout: stdout, stderr: stderr, exitCode: exitCode))
    }
}

public struct ToolProgress: Sendable {
    public let fraction: Double
    public let line: String

    public init(fraction: Double, line: String) {
        self.fraction = fraction
        self.line = line
    }
}

/// Stops a running tool. Two signals are needed: `wit` treats the first as "finish this job".
public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { signal(process) }
    }

    func detach() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if let running { signal(running) }
    }

    private func signal(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            if process.isRunning { process.terminate() }
        }
    }
}

public func runTool(
    _ executable: URL,
    _ arguments: [String],
    cancel: CancelToken? = nil,
    progress: (@Sendable (ToolProgress) -> Void)? = nil
) async throws -> ToolResult {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            cancel?.attach(process)

            let collector = OutputCollector()
            let group = DispatchGroup()
            for (pipe, isError) in [(stdoutPipe, false), (stderrPipe, true)] {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let handle = pipe.fileHandleForReading
                    while true {
                        let chunk = handle.availableData
                        if chunk.isEmpty { break }
                        collector.append(chunk, isError: isError, progress: progress)
                    }
                    group.leave()
                }
            }
            group.wait()
            process.waitUntilExit()
            cancel?.detach()

            let (stdout, stderr) = collector.finish()
            continuation.resume(
                returning: ToolResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr))
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var unfinishedLine = ""

    func append(_ chunk: Data, isError: Bool, progress: (@Sendable (ToolProgress) -> Void)?) {
        let updates = lock.withLock { () -> [ToolProgress] in
            if isError { stderr.append(chunk) } else { stdout.append(chunk) }
            guard progress != nil else { return [] }
            unfinishedLine += String(decoding: chunk, as: UTF8.self)
            let lines = unfinishedLine.split(omittingEmptySubsequences: false) { $0 == "\r" || $0 == "\n" || $0 == "\r\n" }
            unfinishedLine = lines.last.map(String.init) ?? ""
            return lines.dropLast().compactMap { line in
                ToolOutput.progressFraction(in: String(line)).map { ToolProgress(fraction: $0, line: String(line)) }
            }
        }
        if let progress { updates.forEach(progress) }
    }

    func finish() -> (String, String) {
        lock.withLock { (String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self)) }
    }
}
