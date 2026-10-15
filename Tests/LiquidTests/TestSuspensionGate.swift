// SPDX-License-Identifier: Apache-2.0
import Foundation

/// A one-shot test barrier whose arrival and release waits respond to cancellation.
/// Host cancellation ends suspension without throwing, so tests still exercise the
/// engine's post-callback cancellation check rather than a cooperative host error.
actor TestSuspensionGate {
    private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let resume = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var start: ContinuousClock.Instant?

    func enter() async {
        start = ContinuousClock().now
        arrival.continuation.yield(())
        arrival.continuation.finish()
        var iterator = resume.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func waitForEntry() async throws {
        var iterator = arrival.stream.makeAsyncIterator()
        guard await iterator.next() != nil else { throw CancellationError() }
    }

    func release() throws -> Duration {
        guard let start else { throw GateFailure.releasedBeforeEntry }
        let interval = start.duration(to: ContinuousClock().now)
        resume.continuation.yield(())
        resume.continuation.finish()
        return interval
    }

    private enum GateFailure: Error { case releasedBeforeEntry }
}
