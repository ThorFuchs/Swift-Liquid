// SPDX-License-Identifier: Apache-2.0
import Foundation
import Darwin
import Liquid

private let requestBytes = 1_048_576
private let sourceBytes = 262_144
private let profile = LiquidLimits(sourceBytes: sourceBytes, outputBytes: 1_048_576)

private enum WireFailure: Error { case invalid(String) }

private func string(_ value: LiquidValue?) -> String? {
    if case .string(let text) = value { return text }; return nil
}
private func object(_ value: LiquidValue?) throws -> LiquidObject {
    if value == nil { return [:] }
    guard case .object(let result) = value else { throw WireFailure.invalid("Expected an object") }
    return result
}
private func admitKeys(_ value: LiquidObject, allowed: Set<String>) throws {
    guard value.entries.allSatisfy({ allowed.contains($0.key) }) else {
        throw WireFailure.invalid("Unsupported option or host register")
    }
}
private func encode(_ value: LiquidValue) throws -> String {
    switch value {
    case .null: return "null"
    case .bool(let value): return value ? "true" : "false"
    case .integer(let value): return String(value)
    case .number(let value):
        guard value.isFinite else { throw WireFailure.invalid("Nonfinite JSON number") }
        return String(value)
    case .string(let value): return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    case .array(let values): return "[" + (try values.map(encode)).joined(separator: ",") + "]"
    case .object(let value):
        return "{" + (try value.entries.map { try encode(.string($0.key)) + ":" + encode($0.value) }).joined(separator: ",") + "}"
    }
}

// After validating JSON syntax, inspect integer lexemes before engine admission.
// The public reader may already have used its finite-Double fallback internally;
// the adapter rejects that out-of-Int value rather than rendering rounded data.
private func admitNumbers(_ bytes: [UInt8]) throws {
    var index = 0
    var quoted = false
    while index < bytes.count {
        let byte = bytes[index]
        if quoted {
            if byte == 92 { index += 2; continue }
            if byte == 34 { quoted = false }
        } else if byte == 34 { quoted = true }
        else if byte == 45 || (48...57).contains(byte) {
            let start = index
            while index < bytes.count && (bytes[index] == 45 || bytes[index] == 43 || bytes[index] == 46 || bytes[index] == 101 || bytes[index] == 69 || (48...57).contains(bytes[index])) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            if !token.contains(".") && !token.contains("e") && !token.contains("E") && Int(token) == nil {
                throw WireFailure.invalid("Integer outside native Int domain")
            }
            continue
        }
        index += 1
    }
}
private func rejectMarkers(_ value: LiquidValue, depth: Int = 0) throws {
    guard depth <= 64 else { throw WireFailure.invalid("Wire value nesting exceeds 64") }
    switch value {
    case .object(let value):
        guard value["_rpc_drop"] == nil, value["_instantiate"] == nil else { throw WireFailure.invalid("Unsupported or nested drop marker") }
        for entry in value.entries { try rejectMarkers(entry.value, depth: depth + 1) }
    case .array(let values): for value in values { try rejectMarkers(value, depth: depth + 1) }
    default: break
    }
}

// The portable standard MethodDrop, not a general Ruby object bridge.
// Its property family is explicitly bounded by the engine's name and work limits.
private func methodDrop(_ name: String) -> LiquidHostObject {
    let lookup: @Sendable (String) async throws -> LiquidValue? = { key in
        let parts = key.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty,
              parts[1].utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        guard let number = Int(parts[1]) else { throw LiquidError.invalidValue("MethodDrop integer outside native Int domain") }
        let result: Int
        switch parts[0] {
        case "echo": result = number
        case "square":
            let (value, overflow) = number.multipliedReportingOverflow(by: number)
            guard !overflow else { throw LiquidError.invalidValue("MethodDrop integer overflow") }
            result = value
        case "double":
            let (value, overflow) = number.multipliedReportingOverflow(by: 2)
            guard !overflow else { throw LiquidError.invalidValue("MethodDrop integer overflow") }
            result = value
        default: return nil
        }
        return .string(String(result))
    }
    return LiquidHostObject(name, dynamicProperties: [
        LiquidHostDynamicProperty(prefix: "echo_", body: lookup),
        LiquidHostDynamicProperty(prefix: "square_", body: lookup),
        LiquidHostDynamicProperty(prefix: "double_", body: lookup)
    ])
}

// The portable standard IndexDrop uses typed keys; it does not expose Ruby reflection.
private func indexDrop(_ name: String) -> LiquidHostObject {
    let words = ["zero", "one", "two", "three", "four", "five"]
    return LiquidHostObject(name, indexer: LiquidHostIndexer { key in
        switch key {
        case .string(let value): return .string(value)
        case .integer(let value):
            guard value >= -words.count, value < words.count else { return "unknown" }
            return .string(words[value < 0 ? words.count + value : value])
        case .other: return "unknown"
        }
    })
}

// StringDrop is a closed portable test-object shape, never arbitrary Ruby state.
private func stringDropValue(_ parameters: LiquidObject) throws -> String? {
    guard parameters.entries.count <= 1 else { throw WireFailure.invalid("Unsupported StringDrop parameters") }
    guard let value = parameters["value"] else {
        guard parameters.entries.isEmpty else { throw WireFailure.invalid("Unsupported StringDrop parameters") }
        return nil
    }
    switch value {
    case .null: return nil
    case .string(let text): return text
    default: throw WireFailure.invalid("StringDrop value must be text or null")
    }
}

private func admitEnvironment(_ input: LiquidObject) throws -> (LiquidObject, [LiquidHostObject]) {
    var values: [LiquidObject.Entry] = []
    var hosts: [LiquidHostObject] = []
    for entry in input.entries {
        if case .object(let marker) = entry.value, marker["_instantiate"] != nil {
            guard marker.entries.count == 2, let kind = string(marker["_instantiate"]),
                  case .object(let parameters)? = marker["params"] else {
                throw WireFailure.invalid("Unsupported standard drop marker")
            }
            switch kind {
            case "MethodDrop":
                guard parameters.entries.isEmpty else { throw WireFailure.invalid("Unsupported MethodDrop parameters") }
                hosts.append(methodDrop(entry.key))
            case "IndexDrop":
                guard parameters.entries.isEmpty else { throw WireFailure.invalid("Unsupported IndexDrop parameters") }
                hosts.append(indexDrop(entry.key))
            case "BooleanDrop":
                guard parameters.entries.count == 1, case .bool(let value)? = parameters["value"] else {
                    throw WireFailure.invalid("BooleanDrop requires exactly one Boolean value")
                }
                hosts.append(LiquidHostObject(entry.key, booleanValue: value))
            case "NumberDrop":
                guard parameters.entries.count == 1, case .integer(let value)? = parameters["value"] else {
                    throw WireFailure.invalid("NumberDrop requires exactly one integer value")
                }
                hosts.append(LiquidHostObject(entry.key, numberValue: value))
            case "StringDrop":
                hosts.append(LiquidHostObject(entry.key, stringValue: try stringDropValue(parameters)))
            default: throw WireFailure.invalid("Unsupported standard drop marker")
            }
        } else if case .array(let array) = entry.value, array.contains(where: { element in
            if case .object(let object) = element { return object["_instantiate"] != nil }
            return false
        }) {
            var elements: [LiquidHostArrayElement] = []
            for value in array {
                if case .object(let marker) = value, marker["_instantiate"] != nil {
                    guard marker.entries.count == 2, string(marker["_instantiate"]) == "StringDrop",
                          case .object(let parameters)? = marker["params"] else {
                        throw WireFailure.invalid("Unsupported or malformed nested drop marker")
                    }
                    elements.append(.boxedString(try stringDropValue(parameters)))
                } else {
                    try rejectMarkers(value)
                    elements.append(.value(value))
                }
            }
            hosts.append(LiquidHostObject(entry.key, array: elements))
        } else {
            try rejectMarkers(entry.value)
            values.append(entry)
        }
    }
    return (LiquidObject(values), hosts)
}
private func problem(_ error: Error) -> LiquidValue {
    var fields: [LiquidObject.Entry] = []
    switch error {
    case let failure as LiquidRenderFailure:
        let diagnostic = failure.diagnostic
        let prefix = diagnostic.line.map { "Liquid error (\(diagnostic.templateName.map { $0 + " " } ?? "")line \($0)): " } ?? "Liquid error: "
        fields = [.init("type", "render_error"), .init("message", .string(prefix + diagnostic.message))]
        if let line = diagnostic.line { fields.append(.init("line", .integer(line))) }
        if let name = diagnostic.templateName { fields.append(.init("template_name", .string(name))) }
    case LiquidError.syntax(let message, let line, let column):
        fields = [.init("type", "syntax_error"), .init("message", .string(message))]
        if let line { fields.append(.init("line", .integer(line))) }
        if let column { fields.append(.init("column", .integer(column))) }
    case LiquidError.rendering(let message): fields = [.init("type", "render_error"), .init("message", .string(message))]
    case LiquidError.invalidValue(let message): fields = [.init("type", "domain_error"), .init("message", .string(message))]
    case LiquidError.limitExceeded(let name): fields = [.init("type", "operational_error"), .init("message", .string("Limit exceeded: " + name))]
    default: fields = [.init("type", "operational_error"), .init("message", .string(String(describing: error)))]
    }
    return .object(.init(fields))
}
private func rpcError(_ id: LiquidValue, _ code: Int, _ message: String) -> LiquidValue {
    ["jsonrpc": "2.0", "id": id, "error": ["code": .integer(code), "message": .string(message)]]
}

private func rpcError(_ code: Int, _ message: String) -> LiquidValue { rpcError(.null, code, message) }

private struct Compiled {
    let id: String
    let root: LiquidTemplate
    let partials: [String: String]
    let resolver: LiquidTemplateNameResolver
}
private struct Server {
    private var initialized = false
    private var sequence = 0
    private var slot: Compiled?
    private(set) var quitting = false

    mutating func handle(_ data: Data) async -> LiquidValue? {
        let request: LiquidObject
        do {
            guard let text = String(data: data, encoding: .utf8) else { return rpcError(-32700, "Invalid UTF-8 JSON") }
            guard case .object(let value) = try LiquidValue(json: text) else { return rpcError(-32600, "Expected JSON-RPC object") }
            request = value
            // JSON syntax is admitted first, so malformed numbers remain parse errors.
        } catch { return rpcError(-32700, "Invalid JSON") }
        let id = request["id"] ?? .null
        let notification = request["id"] == nil
        guard request["jsonrpc"] == "2.0", let method = string(request["method"]) else { return rpcError(-32600, "Invalid JSON-RPC request") }
        switch id { case .null, .integer, .string: break; default: return rpcError(-32600, "Unsupported request ID") }
        do {
            try admitNumbers(Array(data))
            let params = try object(request["params"])
            let result: LiquidValue
            switch method {
            case "initialize":
                guard string(params["version"]) == "1.0" else { throw WireFailure.invalid("Protocol version must be 1.0") }
                initialized = true
                result = ["version": "1.0", "implementation": "Swift-Liquid LQ1", "liquid_version": "1.3.0+LQ1-development", "features": [],
                          "limits": ["request_bytes": .integer(requestBytes), "source_bytes": .integer(sourceBytes), "active_templates": 1, "output_bytes": .integer(profile.outputBytes)]]
            case "compile":
                slot = nil // Failed compilation cannot accidentally retain prior state.
                guard initialized, let source = string(params["template"]) else { throw WireFailure.invalid("Initialize and supply template before compile") }
                let options = try object(params["options"])
                try admitKeys(options, allowed: ["error_mode", "line_numbers"])
                if let value = options["error_mode"], value != .null, string(value) == nil {
                    throw WireFailure.invalid("error_mode must be text or null")
                }
                if let value = options["line_numbers"], case .bool = value { }
                else if options["line_numbers"] != nil { throw WireFailure.invalid("line_numbers must be Boolean") }
                let mode: LiquidSyntaxMode
                switch string(options["error_mode"]) {
                case nil, "lax": mode = .lax
                case "strict": mode = .strict
                case "strict2": mode = .strict2
                default: throw WireFailure.invalid("Unknown parser mode")
                }
                let hasFilesystem = params["filesystem"] != nil
                let files = try object(params["filesystem"])
                var remaining = sourceBytes - source.utf8.count
                guard remaining >= 0 else { throw WireFailure.invalid("Compiled source capacity exceeded") }
                var supplied: [String: String] = [:]
                for entry in files.entries {
                    guard let text = string(entry.value), supplied.count < 256 else { throw WireFailure.invalid("Invalid or excessive partial map") }
                    remaining -= entry.key.utf8.count + text.utf8.count
                    guard remaining >= 0 else { throw WireFailure.invalid("Compiled source capacity exceeded") }
                    supplied[entry.key] = text
                }
                do {
                    let root = try LiquidTemplate(source, syntaxMode: mode, limits: profile)
                    guard sequence < 200_000 else { throw WireFailure.invalid("Compile request capacity exceeded") }
                    sequence += 1
                    let names = files.entries.map(\.key)
                    let resolver = LiquidTemplateNameResolver(select: { requested in
                        func normalize(_ value: String) -> String {
                            let lower = value.lowercased()
                            return lower.hasSuffix(".liquid") ? lower : lower + ".liquid"
                        }
                        let normalized = normalize(requested)
                        return names.first { normalize($0).caseInsensitiveCompare(normalized) == .orderedSame }
                    }, missing: { name in
                        hasFilesystem ? "Could not find asset " + name : "This liquid context does not allow includes."
                    })
                    let compiled = Compiled(id: "template_\(sequence)", root: root, partials: supplied, resolver: resolver)
                    slot = compiled
                    result = ["template_id": .string(compiled.id)]
                } catch is WireFailure { throw WireFailure.invalid("Compile request capacity exceeded") }
                catch { result = ["template_id": nil, "error": problem(error)] }
            case "render":
                guard initialized, let compiled = slot, string(params["template_id"]) == compiled.id else { throw WireFailure.invalid("Unknown or stale template ID; compile first") }
                let (context, hostObjects) = try admitEnvironment(object(params["environment"]))
                let options = try object(params["options"])
                try admitKeys(options, allowed: ["strict_errors", "resource_limits", "registers"])
                let resourceLimits = try object(options["resource_limits"])
                guard resourceLimits.entries.isEmpty else { throw WireFailure.invalid("Ruby score limits have no equivalent adapter mapping") }
                let registers = try object(options["registers"])
                try admitKeys(registers, allowed: ["current_time"])
                var reference = Date(timeIntervalSince1970: 1_704_067_318)
                if let clock = registers["current_time"] {
                    guard let text = string(clock) else { throw WireFailure.invalid("current_time must be ISO 8601 text") }
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let parsed = formatter.date(from: text) { reference = parsed }
                    else {
                        formatter.formatOptions = [.withInternetDateTime]
                        guard let parsed = formatter.date(from: text) else { throw WireFailure.invalid("Invalid current_time") }
                        reference = parsed
                    }
                }
                let recovering: Bool
                switch options["strict_errors"] {
                case nil, .bool(true)?: recovering = false
                case .bool(false)?: recovering = true
                default: throw WireFailure.invalid("strict_errors must be Boolean")
                }
                let engine = LiquidEngine(limits: profile, referenceTime: reference)
                do {
                    if !hostObjects.isEmpty {
                        guard !recovering, compiled.partials.isEmpty else {
                            throw WireFailure.invalid("Standard Drop requires raising mode and no partials")
                        }
                        result = ["output": .string(try await engine.render(compiled.root, context: context, hostObjects: hostObjects)), "errors": []]
                    } else if recovering {
                        let rendered = try await engine.renderWithDiagnostics(compiled.root, context: context, partialSources: compiled.partials, resolver: compiled.resolver)
                        result = ["output": .string(rendered.output), "errors": .array(rendered.diagnostics.map { diagnostic in
                            var fields: [LiquidObject.Entry] = [.init("type", "render_error"), .init("message", .string(diagnostic.message))]
                            if let line = diagnostic.line { fields.append(.init("line", .integer(line))) }
                            if let name = diagnostic.templateName { fields.append(.init("template_name", .string(name))) }
                            return .object(.init(fields))
                        })]
                    } else { result = ["output": .string(try await engine.renderLocatingFailures(compiled.root, context: context, partialSources: compiled.partials, resolver: compiled.resolver)), "errors": []] }
                } catch { result = ["output": nil, "error": problem(error), "errors": []] }
            case "quit": slot = nil; quitting = true; result = [:]
            default:
                if notification { return nil }
                return rpcError(id, -32601, "Unknown method")
            }
            if notification { return nil }
            return ["jsonrpc": "2.0", "id": id, "result": result]
        } catch WireFailure.invalid(let message) {
            if notification { return nil }
            return rpcError(id, -32602, message)
        } catch {
            if notification { return nil }
            return rpcError(id, -32603, "Internal protocol failure")
        }
    }
}

@main private struct LiquidSpecMain {
    static func main() async {
        var server = Server()
        var line = Data()
        var requests = 0
        do {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count) }
                if count == 0 { break }
                if count < 0 {
                    if errno == EINTR { continue }
                    throw WireFailure.invalid("stdin read failed")
                }
                for byte in buffer.prefix(count) {
                    if byte == 10 {
                        requests += 1
                        guard requests <= 200_000 else { throw WireFailure.invalid("Request count exceeded") }
                        if let response = await server.handle(line) { try write(response) }
                        line.removeAll(keepingCapacity: true)
                        if server.quitting { return }
                    } else {
                        guard line.count < requestBytes else {
                            try write(rpcError(-32600, "Request byte capacity exceeded")); return
                        }
                        line.append(byte)
                    }
                }
            }
            if !line.isEmpty { try write(rpcError(-32700, "Unterminated JSON-RPC frame")) }
        } catch {
            // I/O failure is not a successful protocol render.
            Foundation.exit(1)
        }
    }
    private static func write(_ value: LiquidValue) throws {
        try FileHandle.standardOutput.write(contentsOf: Data((try encode(value) + "\n").utf8))
    }
}
