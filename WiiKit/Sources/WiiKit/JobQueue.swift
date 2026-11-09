import Foundation
import Observation

public enum JobState: Equatable, Sendable {
    case queued, running, finished, failed(String), cancelled

    public var label: String {
        switch self {
        case .queued: return "Waiting"
        case .running: return "Running"
        case .finished: return "Done"
        case .failed(let reason): return reason
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool { self == .queued || self == .running }
}

public struct JobContext: Sendable {
    public let cancel: CancelToken
    public let progress: @Sendable (ToolProgress) -> Void
}

@MainActor @Observable
public final class Job: Identifiable {
    public let id = UUID()
    public let gameID: String
    public let title: String
    public let action: String
    public fileprivate(set) var state: JobState = .queued
    public fileprivate(set) var fraction: Double?
    public fileprivate(set) var detail = ""

    @ObservationIgnored fileprivate let token = CancelToken()
    @ObservationIgnored fileprivate let work: @Sendable (JobContext) async throws -> Void
    @ObservationIgnored fileprivate let completion: @MainActor (JobState) -> Void

    fileprivate init(
        gameID: String, title: String, action: String,
        work: @escaping @Sendable (JobContext) async throws -> Void,
        completion: @escaping @MainActor (JobState) -> Void
    ) {
        self.gameID = gameID
        self.title = title
        self.action = action
        self.work = work
        self.completion = completion
    }
}

public struct JobRecord: Identifiable, Sendable {
    public let id = UUID()
    public let gameID: String
    public let title: String
    public let action: String
    public let result: String
    public let succeeded: Bool
    public let date: Date
}

/// Runs long operations one at a time, so two copies never contend for the same drive.
@MainActor @Observable
public final class JobQueue {
    public private(set) var jobs: [Job] = []
    public var log: [JobRecord] = []
    public private(set) var recentlyFinished = Set<String>()
    public private(set) var batchTotal = 0
    public private(set) var batchDone = 0

    /// Called after each job that touched a game, while the queue may still be working.
    @ObservationIgnored public var onGameFinished: (@MainActor () -> Void)?
    /// Called once the queue has nothing left to do.
    @ObservationIgnored public var onDrained: (@MainActor () -> Void)?

    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var sleepAssertion: NSObjectProtocol?
    @ObservationIgnored private let completionFlash: Duration

    public init(completionFlash: Duration = .seconds(1.3)) {
        self.completionFlash = completionFlash
    }

    public var runningJob: Job? { jobs.first { $0.state == .running } }
    public var activeCount: Int { jobs.filter(\.state.isActive).count }
    public var isBusy: Bool { activeCount > 0 }

    /// The queued or running job for a game. Finished jobs stay listed until the queue drains.
    public func activeJob(for gameID: String) -> Job? {
        jobs.first { $0.gameID == gameID && $0.state.isActive }
    }

    public func enqueue(
        gameID: String = "", title: String, action: String,
        work: @escaping @Sendable (JobContext) async throws -> Void,
        completion: @escaping @MainActor (JobState) -> Void = { _ in }
    ) {
        jobs.append(Job(gameID: gameID, title: title, action: action, work: work, completion: completion))
        batchTotal += 1
        startIfIdle()
    }

    public func cancel(_ job: Job) {
        if job.state == .queued {
            finish(job, as: .cancelled)
            jobs.removeAll { $0.id == job.id }
            batchTotal = max(0, batchTotal - 1)
        } else {
            job.token.cancel()
        }
    }

    /// Cancels everything and waits for the running tool to stop and clean up after itself.
    public func cancelAll() async {
        jobs.filter { $0.state == .queued }.forEach(cancel)
        runningJob.map(cancel)
        await runner?.value
    }

    /// Adds an entry to the history for work that doesn't go through the queue.
    public func note(title: String, action: String, result: String, succeeded: Bool) {
        log.insert(JobRecord(gameID: "", title: title, action: action, result: result, succeeded: succeeded, date: .now), at: 0)
    }

    private func startIfIdle() {
        guard runner == nil else { return }
        // A long queue shouldn't be interrupted by the Mac going to sleep.
        sleepAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated], reason: "Copying games")
        runner = Task {
            while let job = jobs.first(where: { $0.state == .queued }) {
                await run(job)
            }
            drain()
        }
    }

    private func run(_ job: Job) async {
        job.state = .running
        let context = JobContext(cancel: job.token) { update in
            let detail = ToolOutput.rateAndETA(in: update.line).map { "\($0.rate), \($0.eta) left" }
            Task { @MainActor in
                guard job.state == .running else { return }
                job.fraction = update.fraction
                if let detail { job.detail = detail }
            }
        }
        do {
            try await job.work(context)
            finish(job, as: .finished)
        } catch is OperationCancelled {
            finish(job, as: .cancelled)
        } catch {
            finish(job, as: .failed(error.localizedDescription))
        }
        batchDone += 1
        guard !job.gameID.isEmpty else { return }
        if job.state == .finished { flash(job.gameID) }
        onGameFinished?()
    }

    private func finish(_ job: Job, as state: JobState) {
        job.state = state
        if state == .finished { job.fraction = 1 }
        log.insert(
            JobRecord(
                gameID: job.gameID, title: job.title, action: job.action, result: state.label,
                succeeded: state == .finished, date: .now),
            at: 0)
        job.completion(state)
    }

    private func drain() {
        runner = nil
        jobs.removeAll { !$0.state.isActive }
        batchTotal = 0
        batchDone = 0
        if let sleepAssertion { ProcessInfo.processInfo.endActivity(sleepAssertion) }
        sleepAssertion = nil
        onDrained?()
    }

    /// Briefly marks a game's cover to show its work just completed.
    private func flash(_ gameID: String) {
        recentlyFinished.insert(gameID)
        Task {
            try? await Task.sleep(for: completionFlash)
            recentlyFinished.remove(gameID)
        }
    }
}
