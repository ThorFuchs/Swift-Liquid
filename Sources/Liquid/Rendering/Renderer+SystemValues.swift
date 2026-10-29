// SPDX-License-Identifier: Apache-2.0
import Foundation

// Invocation-owned runtime form. It has no public or cross-render identity.
internal struct SystemRuntimeValue {
    let primary: Any
    let descriptor: LiquidSystemDescriptor?
    let plain: LiquidSystemValue.Plain
    let htmlText: LiquidSystemValue.HTML
    let html: LiquidSystemValue.HTML
}

extension Renderer {
    internal func systemPrimary(_ value: Any) -> Any {
        (value as? SystemRuntimeValue)?.primary ?? value
    }

    internal func systemRuntime(_ value: LiquidSystemValue, depth: Int = 1) throws -> Any {
        try budget.filterValue(depth: depth)
        switch value {
        case .ordinary(let ordinary): return try systemOrdinaryRuntime(ordinary, depth: depth, chargeRoot: false)
        case .array(let children):
            guard children.count <= budget.remainingValues else { throw LiquidError.limitExceeded("contextValues") }
            return try children.map { try systemRuntime($0, depth: depth + 1) }
        case .object(let entries):
            guard entries.count <= budget.remainingValues else { throw LiquidError.limitExceeded("contextValues") }
            var pairs: [(String, Any)] = []
            for entry in entries {
                try budget.step()
                pairs.append((entry.name, try systemRuntime(entry.value, depth: depth + 1)))
            }
            return RuntimeObject(uniqueKeysWithValues: pairs)
        case .decorated(let decoration):
            let primary = try systemRuntime(decoration.primary, depth: depth + 1)
            return SystemRuntimeValue(primary: primary, descriptor: decoration.descriptor,
                                      plain: decoration.plain, htmlText: decoration.htmlText, html: decoration.html)
        }
    }

    internal func systemOrdinaryRuntime(_ value: LiquidValue, depth: Int = 1, chargeRoot: Bool = true) throws -> Any {
        if chargeRoot { try budget.filterValue(depth: depth) }
        switch value {
        case .null: return NSNull()
        case .bool(let value): return value
        case .integer(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let values):
            guard values.count <= budget.remainingValues else { throw LiquidError.limitExceeded("contextValues") }
            return try values.map { try systemOrdinaryRuntime($0, depth: depth + 1) }
        case .object(let object):
            guard object.entries.count <= budget.remainingValues else { throw LiquidError.limitExceeded("contextValues") }
            var pairs: [(String, Any)] = []
            for entry in object.entries {
                try budget.step()
                pairs.append((entry.key, try systemOrdinaryRuntime(entry.value, depth: depth + 1)))
            }
            return RuntimeObject(uniqueKeysWithValues: pairs)
        }
    }

    internal func systemAccess(_ property: LiquidSystemProperty, from value: Any) throws -> Any {
        // System lookups share the invocation's finite context-visit budget.
        try budget.filterValue(depth: 1)
        guard let value = value as? SystemRuntimeValue else {
            throw LiquidSystemError.unavailable(property: property, state: .notAdmitted)
        }
        switch property {
        case .value:
            var bridge = FilterValueBridge(budget: budget, allowSystemValues: true)
            let ordinary = try bridge.read(value.primary)
            return try systemOrdinaryRuntime(ordinary)
        case .descriptor:
            guard let descriptor = value.descriptor else {
                throw LiquidSystemError.unavailable(property: .descriptor, state: .notAdmitted)
            }
            guard descriptor.entries.count <= budget.remainingValues else { throw LiquidError.limitExceeded("contextValues") }
            var pairs: [(String, Any)] = []
            for entry in descriptor.entries {
                try budget.filterValue(depth: 1)
                let item: Any
                switch entry.value {
                case .text(let text): item = text
                case .boolean(let value): item = value
                case .typeNames(let names):
                    guard names.count <= budget.remainingValues else { throw LiquidError.limitExceeded("contextValues") }
                    for _ in names { try budget.filterValue(depth: 1) }
                    item = names as [Any]
                }
                pairs.append((entry.name, item))
            }
            return RuntimeObject(uniqueKeysWithValues: pairs)
        case .plain:
            switch value.plain {
            case .qualified(let text): return text
            case .notRequested: throw LiquidSystemError.unavailable(property: property, state: .notRequested)
            case .unavailable(let reason): throw LiquidSystemError.unavailable(property: property, state: .unavailable(reason))
            case .optionalFailure(let reason): throw LiquidSystemError.unavailable(property: property, state: .optionalFailure(reason))
            }
        case .htmlText, .html:
            let slot = property == .htmlText ? value.htmlText : value.html
            switch slot {
            case .qualified(let text, _): return SafeHTML(text)
            case .notRequested: throw LiquidSystemError.unavailable(property: property, state: .notRequested)
            case .unavailable(let reason): throw LiquidSystemError.unavailable(property: property, state: .unavailable(reason))
            case .optionalFailure(let reason): throw LiquidSystemError.unavailable(property: property, state: .optionalFailure(reason))
            }
        }
    }
}
