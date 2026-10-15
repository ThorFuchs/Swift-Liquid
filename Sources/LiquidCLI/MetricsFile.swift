// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

/// CLI-owned I/O; the library only returns immutable observations.
struct MetricsFile {
    let url: URL

    init(path: String, inputs: [URL], output: String?) throws {
        guard path != "-" else { throw MetricsFileError("--metrics requires a file path, not stdout") }
        let destination = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let parent = destination.deletingLastPathComponent()
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue,
              manager.isWritableFile(atPath: parent.path) else {
            throw MetricsFileError("Metrics parent directory must exist and be writable")
        }
        if manager.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { throw MetricsFileError("Metrics destination must be a regular file") }
        }
        let sensitive = try parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames ?? false
        let protected = inputs + (output.map { [URL(fileURLWithPath: $0)] } ?? [])
        for original in protected {
            let other = original.standardizedFileURL.resolvingSymlinksInPath()
            let samePath = sensitive ? destination.path == other.path
                : destination.path.compare(other.path, options: [.caseInsensitive]) == .orderedSame
            if samePath || Self.sameFile(destination, other) {
                throw MetricsFileError("Metrics destination must not alias an input or output file")
            }
        }
        url = destination
    }

    private static func sameFile(_ first: URL, _ second: URL) -> Bool {
        let manager = FileManager.default
        guard let lhs = try? manager.attributesOfItem(atPath: first.path),
              let rhs = try? manager.attributesOfItem(atPath: second.path),
              let leftDevice = lhs[.systemNumber] as? NSNumber,
              let rightDevice = rhs[.systemNumber] as? NSNumber,
              let leftFile = lhs[.systemFileNumber] as? NSNumber,
              let rightFile = rhs[.systemFileNumber] as? NSNumber else { return false }
        return leftDevice == rightDevice && leftFile == rightFile
    }

    func write(_ metrics: LiquidRenderMetrics) throws {
        let object: [String: Any] = [
            "schemaVersion": 1, "totalNanoseconds": try Self.nanoseconds(metrics.totalDuration),
            "parseNanoseconds": try metrics.parseDuration.map(Self.nanoseconds) as Any? ?? NSNull(),
            "sourceBytes": metrics.sourceBytes, "outputBytes": metrics.outputBytes,
            "renderSteps": metrics.renderSteps, "loopIterations": metrics.loopIterations,
            "admittedValues": metrics.admittedValues
        ]
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private static func nanoseconds(_ duration: Duration) throws -> Int64 {
        let components = duration.components
        let (seconds, multipliedOverflow) = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let (total, addedOverflow) = seconds.addingReportingOverflow(components.attoseconds / 1_000_000_000)
        guard !multipliedOverflow, !addedOverflow, total >= 0 else {
            throw MetricsFileError("Metric duration exceeds nonnegative Int64 nanoseconds")
        }
        return total
    }
}

private struct MetricsFileError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
