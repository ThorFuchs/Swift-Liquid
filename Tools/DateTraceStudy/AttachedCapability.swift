import Foundation
import os
@main struct AttachedCapability {
    @inline(never) nonisolated static func checked(_ value: Int) async throws -> Int {
        try Task.checkCancellation()
        return value &+ 1
    }
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let files = FileManager.default
        try Data("ready".utf8).write(to: directory.appendingPathComponent("ready"))
        while !files.fileExists(atPath: directory.appendingPathComponent("start").path) { try await Task.sleep(for: .milliseconds(20)) }
        let poster = OSSignposter(subsystem: "org.swift-liquid.trace-capability", category: .pointsOfInterest)
        let interval = poster.beginInterval("CapabilityBatch")
        var value = 0
        for _ in 0..<100 { value = try await checked(value) }
        poster.endInterval("CapabilityBatch", interval)
        guard value == 100 else { fatalError("Wrong capability result") }
        try Data("100".utf8).write(to: directory.appendingPathComponent("done"))
        while !files.fileExists(atPath: directory.appendingPathComponent("release").path) { try await Task.sleep(for: .milliseconds(20)) }
        print("Attached capability verified: \(value)")
    }
}
