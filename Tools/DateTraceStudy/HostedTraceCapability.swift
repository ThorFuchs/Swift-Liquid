import Foundation
import os
@main struct BoundedCapability {
    @inline(never) nonisolated static func checked(_ value: Int) async throws -> Int {
        try Task.checkCancellation()
        return value &+ 1
    }
    @MainActor static func main() async throws {
        let poster = OSSignposter(subsystem: "org.swift-liquid.trace-capability", category: .pointsOfInterest)
        let interval = poster.beginInterval("CapabilityBatch")
        var value = 0
        for _ in 0..<100 { value = try await checked(value) }
        poster.endInterval("CapabilityBatch", interval)
        guard value == 100 else { fatalError("Wrong capability result") }
        print("Capability result verified: \(value)")
    }
}
