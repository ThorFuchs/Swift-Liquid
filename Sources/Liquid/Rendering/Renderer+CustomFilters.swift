// SPDX-License-Identifier: Apache-2.0
import Foundation

extension Renderer {
    internal func applyCustomFilter(_ filter: LiquidFilter, syntax: Filter, input: Any) async throws -> Any {
        var incoming = FilterValueBridge(budget: budget)
        let value = try incoming.read(input)
        var arguments: [LiquidValue] = []
        for expression in syntax.arguments {
            arguments.append(try incoming.read(try await evaluateFilterArgumentFast(expression)))
        }
        var named: [LiquidObject.Entry] = []
        for argument in syntax.namedArguments {
            try incoming.key(argument.name)
            let value = try incoming.read(try await evaluateFilterArgumentFast(argument.value))
            named.append(.init(argument.name, value))
        }
        try budget.step()
        let result: LiquidValue
        do {
            result = try await filter.body(value, arguments, LiquidObject(named))
        } catch {
            try Task.checkCancellation()
            if let failure = error as? LiquidFilterFailure {
                let renderError = RenderError.filterError(filter.name, underlying: failure.message)
                try budget.output(renderError.message)
                throw renderError
            }
            throw error
        }
        try budget.step()
        var outgoing = FilterValueBridge(budget: budget)
        return try outgoing.write(result)
    }
}

// Each boundary has a byte capacity; value visits and evaluator work share the
// invocation's cumulative budget. The untyped evaluator never crosses the callback.
private struct FilterValueBridge {
    let budget: RuntimeBudget
    private var bytes = 0

    init(budget: RuntimeBudget) { self.budget = budget }

    mutating func key(_ string: String) throws {
        let count = string.utf8.count
        guard count <= budget.limits.outputBytes - bytes else { throw LiquidError.limitExceeded("outputBytes") }
        bytes += count
    }

    private func container(_ count: Int) throws {
        guard count <= budget.remainingValues else { throw LiquidError.limitExceeded("contextValues") }
    }

    mutating func read(_ value: Any, depth: Int = 1) throws -> LiquidValue {
        try budget.filterValue(depth: depth)
        switch value {
        case is NSNull: return .null
        case let value as Bool: return .bool(value)
        case let value as Int: return .integer(value)
        case let value as Double:
            guard value.isFinite else { throw LiquidError.invalidValue("Custom filter numbers must be finite") }
            return .number(value)
        case let value as String:
            try key(value)
            return .string(value)
        case let values as [Any]:
            try container(values.count)
            return .array(try values.map { try read($0, depth: depth + 1) })
        case let value as RuntimeObject:
            try container(value.count)
            var entries: [LiquidObject.Entry] = []
            for entry in value {
                try key(entry.key)
                entries.append(.init(entry.key, try read(entry.value, depth: depth + 1)))
            }
            return .object(LiquidObject(entries))
        case let value as [String: Any]:
            try container(value.count)
            var entries: [LiquidObject.Entry] = []
            for (name, element) in value.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }) {
                try key(name)
                entries.append(.init(name, try read(element, depth: depth + 1)))
            }
            return .object(LiquidObject(entries))
        case let range as RuntimeRange:
            if range.start > range.end { return .array([]) }
            let (distance, overflow) = range.end.subtractingReportingOverflow(range.start)
            guard !overflow, distance < budget.remainingValues else { throw LiquidError.limitExceeded("contextValues") }
            return .array(try (range.start...range.end).map { try read($0, depth: depth + 1) })
        case is LiquidSpecialValue:
            throw LiquidError.invalidValue("Custom filters do not accept blank or empty comparison literals")
        default:
            throw LiquidError.invalidValue("Unsupported value at a custom filter boundary")
        }
    }

    mutating func write(_ value: LiquidValue, depth: Int = 1) throws -> Any {
        try budget.filterValue(depth: depth)
        switch value {
        case .null: return NSNull()
        case .bool(let value): return value
        case .integer(let value): return value
        case .number(let value):
            guard value.isFinite else { throw LiquidError.invalidValue("Custom filter numbers must be finite") }
            return value
        case .string(let value):
            try key(value)
            return value
        case .array(let values):
            try container(values.count)
            return try values.map { try write($0, depth: depth + 1) }
        case .object(let value):
            try container(value.entries.count)
            var entries: [(String, Any)] = []
            for entry in value.entries {
                try key(entry.key)
                entries.append((entry.key, try write(entry.value, depth: depth + 1)))
            }
            return RuntimeObject(uniqueKeysWithValues: entries)
        }
    }
}
