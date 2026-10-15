// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid

/// CLI-owned I/O; the library only returns immutable observations.
struct MetricsFile {
    let url: URL

    init(path: String, inputs: [URL], output: String?) throws {
        guard path != "-" else { throw MetricsFileError("--metrics requires a file path, not stdout") }
        let destination = Self.canonicalURL(URL(fileURLWithPath: path))
        let parent = destination.deletingLastPathComponent()
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue,
              manager.isWritableFile(atPath: parent.path) else {
            throw MetricsFileError("Metrics parent directory must exist and be writable")
        }
        if let attributes = try? manager.attributesOfItem(atPath: destination.path) {
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw MetricsFileError("Metrics destination must be a regular file")
            }
        }
        let sensitive = try parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames ?? false
        let protected = inputs + (output.map { [URL(fileURLWithPath: $0)] } ?? [])
        for original in protected {
            let other = Self.canonicalURL(original)
            let samePath = sensitive ? destination.path == other.path
                : destination.path.compare(other.path, options: [.caseInsensitive]) == .orderedSame
            if samePath || Self.sameFile(destination, other) {
                throw MetricsFileError("Metrics destination must not alias an input or output file")
            }
        }
        url = destination
    }

    // Foundation may leave a symlinked parent unresolved when the leaf is absent.
    // Resolve the nearest existing ancestor before restoring nonexistent components.
    private static func canonicalURL(_ original: URL) -> URL {
        var ancestor = original.standardizedFileURL
        var suffix: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            // A dangling link is an existing filesystem entry, not a new regular file.
            if (try? FileManager.default.attributesOfItem(atPath: ancestor.path)) != nil { break }
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath()
        for component in suffix.reversed() { resolved.appendPathComponent(component) }
        return resolved
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
        let parseNanoseconds: Any
        if let duration = metrics.parseDuration { parseNanoseconds = try Self.nanoseconds(duration) }
        else { parseNanoseconds = NSNull() }
        let object: [String: Any] = [
            "schemaVersion": 1, "totalNanoseconds": try Self.nanoseconds(metrics.totalDuration),
            "parseNanoseconds": parseNanoseconds,
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
