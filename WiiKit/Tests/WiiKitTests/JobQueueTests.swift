import XCTest

@testable import WiiKit

private struct Boom: LocalizedError {
    var errorDescription: String? { "boom" }
}

/// Records from concurrent job closures.
private actor Trace {
    var events: [String] = []
    func add(_ event: String) { events.append(event) }
}

@MainActor
final class JobQueueTests: XCTestCase {
    private func drained(_ queue: JobQueue) async {
        for _ in 0..<500 where queue.isBusy || !queue.jobs.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(queue.isBusy, "The queue should have finished")
    }

    func testJobsRunOneAtATimeInOrder() async {
        let queue = JobQueue()
        let trace = Trace()
        for name in ["a", "b", "c"] {
            queue.enqueue(title: name, action: "x") { _ in
                await trace.add("\(name)-start")
                try await Task.sleep(for: .milliseconds(15))
                await trace.add("\(name)-end")
            }
        }
        await drained(queue)
        let events = await trace.events
        XCTAssertEqual(events, ["a-start", "a-end", "b-start", "b-end", "c-start", "c-end"])
    }

    func testAFailureIsRecordedAndLaterJobsStillRun() async {
        let queue = JobQueue()
        let trace = Trace()
        queue.enqueue(title: "bad", action: "x") { _ in throw Boom() }
        queue.enqueue(title: "good", action: "x") { _ in await trace.add("ran") }
        await drained(queue)
        let events = await trace.events
        XCTAssertEqual(events, ["ran"])
        XCTAssertEqual(queue.log.map(\.title), ["good", "bad"], "History is newest first")
        XCTAssertEqual(queue.log.map(\.succeeded), [true, false])
        XCTAssertEqual(queue.log[1].result, "boom")
    }

    func testCompletionReceivesTheFinalState() async {
        let queue = JobQueue()
        var states: [JobState] = []
        queue.enqueue(title: "ok", action: "x") { _ in } completion: { states.append($0) }
        queue.enqueue(title: "no", action: "x") { _ in throw Boom() } completion: { states.append($0) }
        await drained(queue)
        XCTAssertEqual(states, [.finished, .failed("boom")])
    }

    func testCancellingAQueuedJobRemovesItWithoutRunning() async {
        let queue = JobQueue()
        let trace = Trace()
        queue.enqueue(title: "first", action: "x") { _ in try await Task.sleep(for: .milliseconds(60)) }
        queue.enqueue(title: "second", action: "x") { _ in await trace.add("second") }
        queue.cancel(queue.jobs[1])
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.batchTotal, 1)
        await drained(queue)
        let events = await trace.events
        XCTAssertEqual(events, [])
        XCTAssertTrue(queue.log.contains { $0.title == "second" && $0.result == "Cancelled" })
    }

    func testCancellingTheRunningJobSignalsItsToken() async {
        let queue = JobQueue()
        queue.enqueue(title: "long", action: "x") { context in
            while !context.cancel.isCancelled { try await Task.sleep(for: .milliseconds(5)) }
            throw OperationCancelled()
        }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNotNil(queue.runningJob)
        queue.cancel(queue.jobs[0])
        await drained(queue)
        XCTAssertEqual(queue.log.first?.result, "Cancelled")
    }

    /// Quitting relies on this: nothing may still be running once it returns.
    func testCancelAllStopsEverythingBeforeReturning() async {
        let queue = JobQueue()
        let trace = Trace()
        queue.enqueue(title: "running", action: "x") { context in
            while !context.cancel.isCancelled { try await Task.sleep(for: .milliseconds(5)) }
            await trace.add("stopped")
            throw OperationCancelled()
        }
        queue.enqueue(title: "waiting", action: "x") { _ in await trace.add("should not run") }
        try? await Task.sleep(for: .milliseconds(30))
        await queue.cancelAll()
        let events = await trace.events
        XCTAssertEqual(events, ["stopped"])
        XCTAssertFalse(queue.isBusy)
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testCancelAllOnAnIdleQueueReturnsImmediately() async {
        await JobQueue().cancelAll()
    }

    func testFinishedGamesAreNotActiveWhileTheQueueContinues() async {
        let queue = JobQueue()
        queue.enqueue(gameID: "AAAE01", title: "quick", action: "x") { _ in }
        queue.enqueue(gameID: "BBBE01", title: "slow", action: "x") { _ in try await Task.sleep(for: .milliseconds(80)) }
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertNil(queue.activeJob(for: "AAAE01"), "A finished game must not look like it is still waiting")
        XCTAssertNotNil(queue.activeJob(for: "BBBE01"))
        XCTAssertEqual(queue.activeCount, 1)
        await drained(queue)
    }

    func testBatchCountersAdvanceAndReset() async {
        let queue = JobQueue()
        var doneDuringRun: [Int] = []
        queue.onGameFinished = { doneDuringRun.append(queue.batchDone) }
        queue.enqueue(gameID: "A", title: "a", action: "x") { _ in }
        queue.enqueue(gameID: "B", title: "b", action: "x") { _ in }
        XCTAssertEqual(queue.batchTotal, 2)
        await drained(queue)
        XCTAssertEqual(doneDuringRun, [1, 2])
        XCTAssertEqual(queue.batchTotal, 0)
        XCTAssertEqual(queue.batchDone, 0)
    }

    func testDrainCallbackFiresOncePerBatch() async {
        let queue = JobQueue()
        var drains = 0
        queue.onDrained = { drains += 1 }
        queue.enqueue(title: "a", action: "x") { _ in }
        queue.enqueue(title: "b", action: "x") { _ in }
        await drained(queue)
        XCTAssertEqual(drains, 1)
    }

    func testOnlyGameJobsNotifyAndFlash() async {
        let queue = JobQueue(completionFlash: .milliseconds(40))
        var notified = 0
        queue.onGameFinished = { notified += 1 }
        queue.enqueue(title: "download", action: "x") { _ in }
        queue.enqueue(gameID: "RMCE01", title: "copy", action: "x") { _ in }
        await drained(queue)
        XCTAssertEqual(notified, 1)
        XCTAssertTrue(queue.recentlyFinished.contains("RMCE01"))
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(queue.recentlyFinished.isEmpty, "The completion mark must clear itself")
    }

    func testAFailedCopyDoesNotFlashAsComplete() async {
        let queue = JobQueue()
        queue.enqueue(gameID: "RMCE01", title: "copy", action: "x") { _ in throw Boom() }
        await drained(queue)
        XCTAssertTrue(queue.recentlyFinished.isEmpty)
    }

    func testProgressReportsFractionAndRate() async {
        let queue = JobQueue()
        queue.enqueue(title: "copy", action: "x") { context in
            context.progress(ToolProgress(fraction: 0.5, line: "50% copied in 0:01 (42.6 MiB/sec) -> ETA 0:02"))
            try await Task.sleep(for: .milliseconds(60))
        }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(queue.runningJob?.fraction, 0.5)
        XCTAssertEqual(queue.runningJob?.detail, "42.6 MiB/s, 0:02 left")
        await drained(queue)
    }

    func testANewJobAfterDrainStartsANewBatch() async {
        let queue = JobQueue()
        let trace = Trace()
        queue.enqueue(title: "a", action: "x") { _ in await trace.add("a") }
        await drained(queue)
        queue.enqueue(title: "b", action: "x") { _ in await trace.add("b") }
        await drained(queue)
        let events = await trace.events
        XCTAssertEqual(events, ["a", "b"])
    }
}
