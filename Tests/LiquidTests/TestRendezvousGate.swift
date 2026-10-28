// SPDX-License-Identifier: Apache-2.0
import Testing

/// A test rendezvous that releases every suspended participant on cancellation.
/// A failing participant cancels its structured peers, so a failed assertion path
/// can drain the task group instead of leaking checked continuations in CI.
actor TestRendezvousGate {
    let target: Int
    private(set) var arrivals = 0
    private(set) var firstReleaseCount = 0
    private var cancelled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let progress = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))

    init(target: Int) {
        precondition(target > 0)
        self.target = target
    }

    func enter() async {
        guard !cancelled else { return }
        guard !Task.isCancelled else { cancelWaiters(); return }
        arrivals += 1
        progress.continuation.yield(arrivals)
        if arrivals >= target {
            if firstReleaseCount == 0 { firstReleaseCount = arrivals }
            releaseWaiters()
            progress.continuation.finish()
        } else {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if cancelled || Task.isCancelled { continuation.resume() }
                    else { waiters.append(continuation) }
                }
            } onCancel: {
                Task { await self.cancelWaiters() }
            }
        }
    }

    func waitForArrivals(_ count: Int) async throws {
        var iterator = progress.stream.makeAsyncIterator()
        while let value = await iterator.next() {
            if value >= count { return }
        }
        throw CancellationError()
    }

    private func cancelWaiters() {
        cancelled = true
        progress.continuation.finish()
        releaseWaiters()
    }

    private func releaseWaiters() {
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct TestRendezvousGateTests {
    @Test func cancellationBeforeBarrierEntryReleasesSuspendedPeer() async throws {
        let gate = TestRendezvousGate(target: 2)
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask { await gate.enter(); return Task.isCancelled }
            try await gate.waitForArrivals(1)
            group.addTask {
                withUnsafeCurrentTask { $0?.cancel() }
                await gate.enter()
                return Task.isCancelled
            }
            var completed = 0
            var cancelled = 0
            for try await result in group {
                completed += 1
                if result { cancelled += 1 }
            }
            #expect(completed == 2 && cancelled == 1)
        }
        #expect(await gate.firstReleaseCount == 0)
    }

    @Test func cancellationDuringBarrierWaitReleasesAllPeers() async throws {
        let gate = TestRendezvousGate(target: 3)
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<2 {
                group.addTask { await gate.enter(); return Task.isCancelled }
            }
            try await gate.waitForArrivals(2)
            group.cancelAll()
            var completed = 0
            for try await cancelled in group {
                #expect(cancelled)
                completed += 1
            }
            #expect(completed == 2)
        }
        #expect(await gate.firstReleaseCount == 0)
    }

    @Test func cancellationFromThrowingBarrierParticipantDrainsPeers() async throws {
        let gate = TestRendezvousGate(target: 2)
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { await gate.enter() }
                try await gate.waitForArrivals(1)
                group.addTask { throw RendezvousPeerFailure.expected }
                // Propagate the first peer failure out of the group body. The
                // structured cancellation then releases the parked participant.
                for try await _ in group {}
            }
            Issue.record("Expected original peer failure")
        } catch RendezvousPeerFailure.expected {}
        #expect(await gate.firstReleaseCount == 0)
    }
}

private enum RendezvousPeerFailure: Error { case expected }
