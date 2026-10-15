// SPDX-License-Identifier: Apache-2.0
import Foundation
import Liquid
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct LiquidCommand {
    static let version = "1.1.0"
    static let help = """
    Swift-Liquid — Shopify Liquid templates in Swift

    Usage:
      liquid render TEMPLATE [--data JSON] [--partials DIRECTORY] [--output FILE]
      liquid validate TEMPLATE
      liquid analyze TEMPLATE [--format text|json]
      liquid --help
      liquid --version

    TEMPLATE may be '-' to read UTF-8 source from stdin.
    Options:
      --syntax-mode lax|strict|strict2   Parser mode (default: lax)
      --strict-filters                  Fail on unknown filters
      --data JSON                       Context file with a JSON object root
      --partials DIRECTORY              Explicit directory of .liquid partials
      --output FILE                     Atomically write complete rendered output
      --metrics FILE                    Write opt-in render metrics as separate JSON
      --format text|json                Inspection output format (default: text)
    """

    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data("liquid: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run(_ arguments: [String]) async throws {
        if arguments.isEmpty || arguments == ["--help"] || arguments == ["-h"] { print(help); return }
        if arguments == ["--version"] { print("Swift-Liquid \(version)"); return }
        guard let command = arguments.first, ["render", "validate", "analyze"].contains(command) else {
            throw CLIError("Expected render, validate, or analyze; use --help for usage")
        }
        if arguments.dropFirst().contains("--help") { print(help); return }
        var path: String?
        var options: [String: String] = [:]
        var strictFilters = false
        var index = 1
        let valueOptions: Set<String> = ["--data", "--partials", "--output", "--syntax-mode", "--format", "--metrics"]
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--strict-filters" {
                guard !strictFilters else { throw CLIError("Duplicate --strict-filters") }
                strictFilters = true
            } else if valueOptions.contains(argument) {
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--") else { throw CLIError("Missing value for \(argument)") }
                guard options[argument] == nil else { throw CLIError("Duplicate \(argument)") }
                options[argument] = arguments[index]
            } else if argument.hasPrefix("-") && argument != "-" {
                throw CLIError("Unknown option \(argument)")
            } else {
                guard path == nil else { throw CLIError("Expected exactly one template path") }
                path = argument
            }
            index += 1
        }
        guard let path else { throw CLIError("Missing template path") }
        guard let mode = LiquidSyntaxMode(rawValue: options["--syntax-mode"] ?? "lax") else {
            throw CLIError("Syntax mode must be lax, strict, or strict2")
        }
        if command == "validate", options.keys.contains(where: { $0 != "--syntax-mode" }) || strictFilters {
            throw CLIError("validate accepts only --syntax-mode")
        }
        if command == "render", options["--format"] != nil { throw CLIError("render does not accept --format") }
        if command == "analyze" {
            guard !strictFilters, options.keys.allSatisfy({ ["--syntax-mode", "--format"].contains($0) }) else {
                throw CLIError("analyze accepts only --syntax-mode and --format")
            }
            guard ["text", "json"].contains(options["--format"] ?? "text") else {
                throw CLIError("Format must be text or json")
            }
        }
        let source = try readText(path, maximumBytes: LiquidLimits.default.sourceBytes)
        let template = try LiquidTemplate(source, syntaxMode: mode)
        if command == "validate" { print("Valid Liquid template."); return }
        if command == "analyze" {
            let result = try LiquidEngine().inspect(template)
            try writeInspection(result, format: options["--format"] ?? "text")
            return
        }

        let context: LiquidObject
        var inputFiles = path == "-" ? [] : [URL(fileURLWithPath: path)]
        if let dataPath = options["--data"] {
            let value = try LiquidValue(json: readText(dataPath, maximumBytes: 8_388_608))
            guard case .object(let object) = value else { throw CLIError("JSON context root must be an object") }
            context = object
            if dataPath != "-" { inputFiles.append(URL(fileURLWithPath: dataPath)) }
        } else { context = [:] }
        var partials: [String: LiquidTemplate] = [:]
        if let directory = options["--partials"] { partials = try readPartials(directory, syntaxMode: mode, inputFiles: &inputFiles) }
        let metricsFile = try options["--metrics"].map { try MetricsFile(path: $0, inputs: inputFiles, output: options["--output"]) }
        let engine = LiquidEngine(strictFilters: strictFilters)
        let output: String
        let metrics: LiquidRenderMetrics?
        if metricsFile != nil {
            let measured = try await engine.renderWithMetrics(template, context: context, templates: partials)
            output = measured.output; metrics = measured.metrics
        } else {
            output = try await engine.render(template, context: context, templates: partials)
            metrics = nil
        }
        let bytes = Data(output.utf8)
        if let destination = options["--output"] { try bytes.write(to: URL(fileURLWithPath: destination), options: .atomic) }
        else { try FileHandle.standardOutput.write(contentsOf: bytes) }
        if let metricsFile, let metrics { try metricsFile.write(metrics) }
    }

    private static func writeInspection(_ result: LiquidTemplateInspection, format: String) throws {
        let output: String
        if format == "json" {
            let object: [String: Any] = ["schemaVersion": 1, "variableRoots": result.variableRoots,
                "filterNames": result.filterNames, "literalPartialNames": result.literalPartialNames,
                "hasDynamicPartials": result.hasDynamicPartials]
            output = String(decoding: try JSONSerialization.data(withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        } else {
            func list(_ names: [String]) throws -> String {
                String(decoding: try JSONSerialization.data(withJSONObject: names,
                    options: [.withoutEscapingSlashes]), as: UTF8.self)
            }
            output = """
            Variable roots: \(try list(result.variableRoots))
            Filter names: \(try list(result.filterNames))
            Literal partial names: \(try list(result.literalPartialNames))
            Dynamic partial references: \(result.hasDynamicPartials ? "yes" : "no")
            """
        }
        try FileHandle.standardOutput.write(contentsOf: Data((output + "\n").utf8))
    }

    private static func readText(_ path: String, maximumBytes: Int) throws -> String {
        let handle = path == "-" ? FileHandle.standardInput : try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { if path != "-" { try? handle.close() } }
        var bytes = Data()
        while let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - bytes.count)), !chunk.isEmpty {
            bytes.append(chunk)
            guard bytes.count <= maximumBytes else { throw CLIError("Input exceeds \(maximumBytes) bytes") }
        }
        guard let text = String(data: bytes, encoding: .utf8) else { throw CLIError("Input must be valid UTF-8") }
        return text
    }

    private static func readPartials(_ path: String, syntaxMode: LiquidSyntaxMode, inputFiles: inout [URL]) throws -> [String: LiquidTemplate] {
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CLIError("Partial directory does not exist")
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { throw CLIError("Cannot enumerate partial directory") }
        var partials: [String: LiquidTemplate] = [:]
        var remaining = LiquidLimits.default.sourceBytes
        for case let url as URL in enumerator {
            let resource = try url.resourceValues(forKeys: Set(keys))
            if resource.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard resource.isRegularFile == true, url.pathExtension == "liquid" else { continue }
            let source = try readText(url.path, maximumBytes: remaining)
            remaining -= source.utf8.count
            let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
            let rootComponents = root.pathComponents
            guard normalized.pathComponents.starts(with: rootComponents) else { throw CLIError("Partial path escapes its directory") }
            let relative = normalized.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
            let key = String(relative.dropLast(".liquid".count))
            partials[key] = try LiquidTemplate(source, syntaxMode: syntaxMode)
            inputFiles.append(normalized)
        }
        return partials
    }
}

private struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
