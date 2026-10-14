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
    static let version = "0.1.0-dev"
    static let help = """
    Swift-Liquid — Shopify Liquid templates in Swift

    Usage:
      liquid render TEMPLATE [--data JSON] [--partials DIRECTORY] [--output FILE]
      liquid validate TEMPLATE
      liquid --help
      liquid --version

    TEMPLATE may be '-' to read UTF-8 source from stdin.
    Options:
      --syntax-mode lax|strict|strict2   Parser mode (default: lax)
      --strict-filters                  Fail on unknown filters
      --data JSON                       Context file with a JSON object root
      --partials DIRECTORY              Explicit directory of .liquid partials
      --output FILE                     Atomically write complete rendered output
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
        guard let command = arguments.first, ["render", "validate"].contains(command) else {
            throw CLIError("Expected render or validate; use --help for usage")
        }
        if arguments.dropFirst().contains("--help") { print(help); return }
        var path: String?
        var options: [String: String] = [:]
        var strictFilters = false
        var index = 1
        let valueOptions: Set<String> = ["--data", "--partials", "--output", "--syntax-mode"]
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
        let source = try readText(path, maximumBytes: LiquidLimits.default.sourceBytes)
        let template = try LiquidTemplate(source, syntaxMode: mode)
        if command == "validate" { print("Valid Liquid template."); return }

        let context: LiquidObject
        if let dataPath = options["--data"] {
            let value = try LiquidValue(json: readText(dataPath, maximumBytes: 8_388_608))
            guard case .object(let object) = value else { throw CLIError("JSON context root must be an object") }
            context = object
        } else { context = [:] }
        var partials: [String: LiquidTemplate] = [:]
        if let directory = options["--partials"] { partials = try readPartials(directory, syntaxMode: mode) }
        let output = try await LiquidEngine(strictFilters: strictFilters).render(template, context: context, templates: partials)
        let bytes = Data(output.utf8)
        if let destination = options["--output"] { try bytes.write(to: URL(fileURLWithPath: destination), options: .atomic) }
        else { try FileHandle.standardOutput.write(contentsOf: bytes) }
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

    private static func readPartials(_ path: String, syntaxMode: LiquidSyntaxMode) throws -> [String: LiquidTemplate] {
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
        }
        return partials
    }
}

private struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
