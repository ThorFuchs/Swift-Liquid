// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Renderer.swift
//  LiquidRenderer
//
//

import Foundation

internal enum LoopControlSignal: Error {
    case breakLoop
    case continueLoop
    case breakLoopWithOutput(String)
    case continueLoopWithOutput(String)

    var partialOutput: String {
        switch self {
        case .breakLoopWithOutput(let output), .continueLoopWithOutput(let output): return output
        default: return ""
        }
    }
    func carrying(_ output: String) -> Self {
        switch self {
        case .continueLoop, .continueLoopWithOutput: return .continueLoopWithOutput(output)
        case .breakLoop, .breakLoopWithOutput: return .breakLoopWithOutput(output)
        }
    }
}

internal struct RendererConfiguration: Sendable {
    internal let autoEscape: Bool
    
    internal let strictMode: Bool
    
    internal let maxNestingDepth: Int
    
    internal let maxLoopIterations: Int
    
    
    internal init(
        autoEscape: Bool = false,
        strictMode: Bool = false,
        maxNestingDepth: Int = 100,
        maxLoopIterations: Int = 1_000_000,
    ) {
        self.autoEscape = autoEscape
        self.strictMode = strictMode
        self.maxNestingDepth = maxNestingDepth
        self.maxLoopIterations = maxLoopIterations
    }
    
    internal static let `default` = RendererConfiguration()
    
    internal static let secure = RendererConfiguration(
        autoEscape: true,
        strictMode: true,
        maxNestingDepth: 50,
        maxLoopIterations: 100_000
    )
}

internal final class Renderer {
    // MARK: - Properties
    
    internal let budget: RuntimeBudget
    internal let recoveryEnabled: Bool
    internal let referenceTime: Date
    internal var diagnostics: [LiquidDiagnostic] = []
    internal var lastIfChanged: String?
    internal var context: RenderingContext

    internal let configuration: RendererConfiguration

    internal let autoEscapeEnabled: Bool

    internal var customFilters: [String: any CustomFilter]


    internal var templateLoader: TemplateLoader?


    internal var rootTemplatePath: String?

    internal var templatePathStack: [String]








    // MARK: - Initialization
    
    internal init(configuration: RendererConfiguration = .default, limits: LiquidLimits = .default, recoveryEnabled: Bool = false, referenceTime: Date = Date()) {
        self.referenceTime = referenceTime
        self.recoveryEnabled = recoveryEnabled
        self.budget = RuntimeBudget(limits)
        self.context = RenderingContext()
        self.configuration = configuration
        self.autoEscapeEnabled = configuration.autoEscape
        self.customFilters = [:]
        self.templateLoader = nil
        self.rootTemplatePath = nil
        self.templatePathStack = []
        // Set up debug context in RenderingContext
    }

    internal func setCustomFilters(_ filters: [String: any CustomFilter]) {
        self.customFilters = filters
    }



    internal func setTemplateLoader(_ loader: TemplateLoader?, rootTemplatePath: String? = nil) {
        self.templateLoader = loader
        self.rootTemplatePath = rootTemplatePath
        resetTemplatePathStack()
    }




    
    // MARK: - Public Interface
    
    internal func render(_ node: borrowing ASTNode, with variables: RuntimeVariables = [:]) async throws -> String {
        context.setVariables(variables)
        resetTemplatePathStack()
        do { return try await renderNode(node) }
        catch let signal as LoopControlSignal {
            return signal.partialOutput
        }
    }


    
}

// MARK: - Rendering Context

internal final class RenderingContext {
    internal struct VariableSnapshot {
        let name: String
        let storedValue: Any?
        let existed: Bool
        let usedLocalScope: Bool
    }

    private enum PathComponent {
        case size
        case first
        case last
        case index(Int)
        case key(String)
    }

    private struct CachedVariablePath {
        let baseName: String
        let components: [PathComponent]
    }

    private var variables: RuntimeVariables = [:]
    private var scopes: [RuntimeVariables] = []
    private var currentScope: RuntimeVariables?
    private var variablePathCache: [ScalarKey: CachedVariablePath] = [:]
    private var loopDepth: Int = 0
    private var counters: [String: Int] = [:]
    
    
    func setVariables(
        _ vars: RuntimeVariables
    ) {
        variables = vars
        if !scopes.isEmpty {
            scopes.removeAll(keepingCapacity: true)
        }
        currentScope = nil
        loopDepth = 0
        if !counters.isEmpty {
            counters.removeAll(keepingCapacity: true)
        }



    }
    
    func getVariable(_ name: String) -> Any? {
        let value: Any?

        if let path = cachedVariablePath(for: name) {
            switch path.components.count {
            case 0:
                value = lookupValue(named: path.baseName)
            case 1:
                if let baseValue = lookupValue(named: path.baseName) {
                    switch path.components[0] {
                    case .size:
                        if let dict = baseValue as? [String: Any], let v = dict["size"] ?? dict["length"] {
                            value = v
                        } else if let ordered = baseValue as? RuntimeObject, let v = ordered["size"] ?? ordered["length"] {
                            value = v
                        } else if let array = baseValue as? [Any] {
                            value = array.count
                        } else if let string = baseValue as? String {
                            value = string.unicodeScalars.count
                        } else {
                            value = 0
                        }
                    case .first:
                        if let dict = baseValue as? [String: Any], let v = dict["first"] {
                            value = v
                        } else if let ordered = baseValue as? RuntimeObject {
                            if let v = ordered["first"] {
                                value = v
                            } else if !ordered.isEmpty {
                                let first = ordered.elements[0]
                                value = [first.key, first.value] as [Any]
                            } else {
                                value = nil
                            }
                        } else if let string = baseValue as? String {
                            value = string.unicodeScalars.first.map(String.init)
                        } else if let array = baseValue as? [Any], !array.isEmpty {
                            value = array[0]
                        } else {
                            value = nil
                        }
                    case .last:
                        if let dict = baseValue as? [String: Any], let v = dict["last"] {
                            value = v
                        } else if let ordered = baseValue as? RuntimeObject, let v = ordered["last"] {
                            value = v
                        } else if let string = baseValue as? String {
                            value = string.unicodeScalars.last.map(String.init)
                        } else if let array = baseValue as? [Any], !array.isEmpty {
                            value = array[array.count - 1]
                        } else {
                            value = nil
                        }
                    case .index(let index):
                        if let array = baseValue as? [Any], index >= 0 && index < array.count {
                            value = array[index]
                        } else {
                            value = nil
                        }
                    case .key(let key):
                        if let dictionary = baseValue as? [String: Any] {
                            value = dictionary[key]
                        } else if let ordered = baseValue as? RuntimeObject {
                            // Check for special properties first, then dict key
                            if let v = ordered[key] {
                                value = v
                            } else if key == "first", !ordered.isEmpty {
                                let first = ordered.elements[0]
                                value = [first.key, first.value] as [Any]
                            } else if key == "last", !ordered.isEmpty {
                                let lastPair = ordered.elements[ordered.count - 1]
                                value = [lastPair.key, lastPair.value] as [Any]
                            } else if key == "size" || key == "length" {
                                value = ordered.count
                            } else {
                                value = nil
                            }

                        } else {
                            value = resolve(path.components[0], from: baseValue)
                        }
                    }
                } else {
                    value = nil
                }
            default:
                var currentValue = lookupValue(named: path.baseName)
                for component in path.components {
                    guard let resolved = currentValue else {
                        currentValue = nil
                        break
                    }
                    currentValue = resolve(component, from: resolved)
                }
                value = currentValue
            }
        } else {
            value = lookupValue(named: name)
        }

        return value
    }
    
    func setVariable(_ name: String, value: Any) {
        if currentScope != nil {
            currentScope?[name] = value
        } else {
            variables[name] = value
        }

    }

    func setRootVariable(_ name: String, value: Any) {
        variables[name] = value
    }

    func getCounter(_ name: String) -> Int? {
        return counters[name]
    }

    func setCounter(_ name: String, value: Int) {
        counters[name] = value
    }

    
    func pushScope(_ scope: RuntimeVariables = [:]) {
        if let currentScope {
            scopes.append(currentScope)
        }
        currentScope = scope
    }
    
    func popScope() {
        currentScope = scopes.popLast()
    }

    var isInsideLoop: Bool {
        loopDepth > 0
    }

    func enterLoop() {
        loopDepth += 1
    }

    func leaveLoop() {
        if loopDepth > 0 {
            loopDepth -= 1
        }
    }

    internal func snapshotVariables(named names: [String]) -> [VariableSnapshot] {
        let useLocalScope = currentScope != nil

        return names.map { name in
            if useLocalScope {
                let storedValue = currentScope?[name]
                return VariableSnapshot(
                    name: name,
                    storedValue: storedValue,
                    existed: storedValue != nil,
                    usedLocalScope: true
                )
            }

            let storedValue = variables[name]
            return VariableSnapshot(
                name: name,
                storedValue: storedValue,
                existed: storedValue != nil,
                usedLocalScope: false
            )
        }
    }

    internal func restoreVariables(_ snapshots: [VariableSnapshot]) {
        for snapshot in snapshots {
            if snapshot.usedLocalScope, currentScope != nil {
                if snapshot.existed {
                    currentScope?[snapshot.name] = snapshot.storedValue
                } else {
                    currentScope?.removeValue(forKey: snapshot.name)
                }
            } else if snapshot.existed {
                variables[snapshot.name] = snapshot.storedValue
            } else {
                variables.removeValue(forKey: snapshot.name)
            }
        }
    }
    

    
    static func isStaticallyBlankBlock(_ nodes: [ASTNode]) -> Bool {
        for node in nodes {
            switch node {
            case .text(let text):
                if !text.string.allSatisfy(\.isWhitespace) { return false }
            case .assign, .comment, .increment, .decrement, .capture:
                continue
            case .if(_, let thenNodes, let elsifBranches, let elseNodes):
                if !isStaticallyBlankBlock(thenNodes) { return false }
                for (_, branchNodes) in elsifBranches {
                    if !isStaticallyBlankBlock(branchNodes) { return false }
                }
                if let elseNodes, !isStaticallyBlankBlock(elseNodes) { return false }
            case .unless(_, let thenNodes, let elseNodes):
                if !isStaticallyBlankBlock(thenNodes) { return false }
                if let elseNodes, !isStaticallyBlankBlock(elseNodes) { return false }
            case .case(_, let whens, let elseBranch):
                for (_, whenNodes) in whens { if !isStaticallyBlankBlock(whenNodes) { return false } }
                if let elseBranch, !isStaticallyBlankBlock(elseBranch) { return false }
            case .for(_, _, let body, let empty, _):
                if !isStaticallyBlankBlock(body) { return false }
                if let empty, !isStaticallyBlankBlock(empty) { return false }
            case .liquid(let body):
                if !isStaticallyBlankBlock(body) { return false }
            case .output, .echo, .raw:
                return false
            default:
                return false
            }
        }
        return true
    }


    


    struct SavedState {
        let variables: RuntimeVariables
        let scopes: [RuntimeVariables]
        let currentScope: RuntimeVariables?
        let counters: [String: Int]
        let loopDepth: Int
    }

    func saveState() -> SavedState {
        SavedState(
            variables: variables,
            scopes: scopes,
            currentScope: currentScope,
            counters: counters,
            loopDepth: loopDepth
        )
    }

    func restoreState(_ state: SavedState) {
        variables = state.variables
        scopes = state.scopes
        currentScope = state.currentScope
        counters = state.counters
        loopDepth = state.loopDepth
    }

    func isolateScope(with bindings: RuntimeVariables) {
        loopDepth = 0
        variables = [:]
        scopes.removeAll(keepingCapacity: true)
        currentScope = nil
        counters.removeAll(keepingCapacity: true)
        for (key, value) in bindings {
            variables[key] = value
        }
    }











    func getLiteralVariable(_ name: String) -> Any? { lookupValue(named: name) }

    private func lookupValue(named name: String) -> Any? {
        // Check current scope first
        if let currentScope,
           let value = currentScope[name] {
            return value
        }
        // Check parent scopes (for nested loop variables like forloop/parentloop)
        for scope in scopes.reversed() {
            if let value = scope[name] {
                return value
            }
        }
        // Check normal variables first, then fall back to counter namespace
        if let value = variables[name] {
            return value
        }
        // Fall back to increment/decrement counter namespace
        if let counter = counters[name] {
            return counter
        }
        return nil
    }









    private func cachedVariablePath(for name: String) -> CachedVariablePath? {
        if let cached = variablePathCache[ScalarKey(name)] {
            return cached
        }

        guard name.contains(".") else {
            return nil
        }

        let rawComponents = name.split(separator: ".")
        guard let first = rawComponents.first else {
            return nil
        }

        let cached = makeCachedVariablePath(
            baseName: String(first),
            components: rawComponents.dropFirst()
        )
        if variablePathCache.count > 512 {
            variablePathCache.removeAll(keepingCapacity: true)
        }
        variablePathCache[ScalarKey(name)] = cached
        return cached
    }



    @inline(__always)
    private func makeCachedVariablePath<S: Sequence>(
        baseName: String,
        components: S
    ) -> CachedVariablePath where S.Element: StringProtocol {
        var parsedComponents: [PathComponent] = []
        let rawComponents = Array(components)
        parsedComponents.reserveCapacity(rawComponents.count)

        for rawComponent in rawComponents {
            switch rawComponent {
            case "size", "length":
                parsedComponents.append(.size)
            case "first":
                parsedComponents.append(.first)
            case "last":
                parsedComponents.append(.last)
            default:
                if let index = Int(rawComponent) {
                    parsedComponents.append(.index(index))
                } else {
                    parsedComponents.append(.key(String(rawComponent)))
                }
            }
        }

        return CachedVariablePath(
            baseName: baseName,
            components: parsedComponents
        )
    }

    private func resolve(_ component: PathComponent, from value: Any) -> Any? {
        switch component {
        case .size:
            // Dictionary key "size" or "length" takes priority (e.g., forloop.length)
            if let dict = value as? [String: Any] {
                if let val = dict["size"] { return val }
                if let val = dict["length"] { return val }
            }
            if let ordered = value as? RuntimeObject {
                if let val = ordered["size"] { return val }
                if let val = ordered["length"] { return val }
            }
            if let array = value as? [Any] {
                return array.count
            } else if let string = value as? String {
                return string.count
            }
            return 0

        case .first:
            // Dictionary key "first" takes priority (e.g., forloop.first)
            if let dict = value as? [String: Any], let val = dict["first"] {
                return val
            }
            if let ordered = value as? RuntimeObject, let val = ordered["first"] {
                return val
            }
            if let array = value as? [Any], !array.isEmpty {
                return array[0]
            }
            return nil

        case .last:
            // Dictionary key "last" takes priority (e.g., forloop.last)
            if let dict = value as? [String: Any], let val = dict["last"] {
                return val
            }
            if let ordered = value as? RuntimeObject, let val = ordered["last"] {
                return val
            }
            if let array = value as? [Any], !array.isEmpty {
                return array[array.count - 1]
            }
            return nil

        case .index(let index):
            if let array = value as? [Any], index >= 0 && index < array.count {
                return array[index]
            }
            return nil

        case .key(let key):
            if let dictionary = value as? [String: Any] {
                return dictionary[key]
            }
            if let ordered = value as? RuntimeObject {
                return ordered[key]
            }


            let mirror = Mirror(reflecting: value)
            for child in mirror.children where child.label == key {
                return child.value
            }
            return nil
        }
    }



    private func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}

// MARK: - Async Extensions

extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self {
            results.append(try await transform(element))
        }
        return results
    }
}
