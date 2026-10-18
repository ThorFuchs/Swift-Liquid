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
        guard value["_rpc_drop"] == nil else { throw WireFailure.invalid("Drop callbacks are unsupported") }
        for entry in value.entries { try rejectMarkers(entry.value, depth: depth + 1) }
    case .array(let values): for value in values { try rejectMarkers(value, depth: depth + 1) }
    default: break
    }
}
private func problem(_ error: Error) -> LiquidValue {
    var fields: [LiquidObject.Entry] = []
    switch error {
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
    let partials: [String: LiquidTemplate]
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
                    let partials = try supplied.mapValues { try LiquidTemplate($0, syntaxMode: mode, limits: profile) }
                    guard sequence < 200_000 else { throw WireFailure.invalid("Compile request capacity exceeded") }
                    sequence += 1
                    let compiled = Compiled(id: "template_\(sequence)", root: root, partials: partials)
                    slot = compiled
                    result = ["template_id": .string(compiled.id)]
                } catch is WireFailure { throw WireFailure.invalid("Compile request capacity exceeded") }
                catch { result = ["template_id": nil, "error": problem(error)] }
            case "render":
                guard initialized, let compiled = slot, string(params["template_id"]) == compiled.id else { throw WireFailure.invalid("Unknown or stale template ID; compile first") }
                let context = try object(params["environment"])
                try rejectMarkers(.object(context))
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
                    if recovering {
                        let rendered = try await engine.renderWithDiagnostics(compiled.root, context: context, templates: compiled.partials)
                        result = ["output": .string(rendered.output), "errors": .array(rendered.diagnostics.map { diagnostic in
                            var fields: [LiquidObject.Entry] = [.init("type", "render_error"), .init("message", .string(diagnostic.message))]
                            if let line = diagnostic.line { fields.append(.init("line", .integer(line))) }
                            if let name = diagnostic.templateName { fields.append(.init("template_name", .string(name))) }
                            return .object(.init(fields))
                        })]
                    } else { result = ["output": .string(try await engine.render(compiled.root, context: context, templates: compiled.partials)), "errors": []] }
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
