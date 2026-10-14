// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  LiquidExpression.swift
//  LiquidCore
//
//

import Foundation

internal indirect enum LiquidExpression: Sendable, Equatable {
    // MARK: - Basic Values
    
    case literal(Value)
    
    case variable(InlineString)
    
    // MARK: - Operations
    
    case binary(left: LiquidExpression, op: BinaryOp, right: LiquidExpression)
    
    case unary(op: UnaryOp, expr: LiquidExpression)
    
    case range(start: LiquidExpression, end: LiquidExpression)
    
    // MARK: - Filters and Tests
    
    case filtered(expr: LiquidExpression, filters: [Filter])
    
    case test(expr: LiquidExpression, test: TestOp)
    
    // MARK: - Collection Access
    
    case access(expr: LiquidExpression, key: LiquidExpression)
    
    case call(name: InlineString, arguments: [CallArgument])
}

internal struct CallArgument: Sendable, Equatable {
    internal let label: InlineString?
    internal let value: LiquidExpression

    internal init(label: InlineString? = nil, value: LiquidExpression) {
        self.label = label
        self.value = value
    }
}

extension CallArgument {
    internal var containsVariables: Bool {
        value.containsVariables
    }

    internal var referencedVariables: Set<String> {
        value.referencedVariables
    }

    internal var complexityScore: Int {
        value.complexityScore
    }
}

// MARK: - Value Types

internal enum Value: Sendable, Equatable, Hashable {
    case string(InlineString)
    
    case number(Double, isFloat: Bool = false)
    case integer(Int)
    
    case boolean(Bool)
    
    case null
    case special(LiquidSpecialValue)
    
    case array([Value])
    
    case dictionary([String: Value])
}

// MARK: - Filter Type

internal struct NamedFilterArgument: Sendable, Equatable {
    let name: String
    let value: LiquidExpression
}

internal struct Filter: Sendable, Equatable {
    internal enum BuiltinKind: UInt8, Sendable, Equatable {
        case upcase
        case downcase
        case capitalize
        case size
        case first
        case last
        case strip
        case reverse
        case raw
        case escape
        case escapeOnce
        case lstrip
        case rstrip
        case abs
        case date
        case json
        case sum
        case uniq
        case compact
        case slugify
        case join
        case split
        case append
        case prepend
        case plus
        case minus
        case times
        case dividedBy
        case round
        case atLeast
        case atMost
        case map
        case sort
        case limit
        case offset
        case `default`
        case ceil
        case floor
        case truncate
        case truncatewords
        case stripHTML
        case stripNewlines
        case newlineToBr
        case urlEncode
        case urlDecode
        case base64Encode
        case base64Decode
        case `where`
    }

    internal let name: InlineString
    
    internal let arguments: [LiquidExpression]
    
    internal let namedArguments: [NamedFilterArgument]

    internal let builtinKind: BuiltinKind?
    internal let singleLiteralIntegerArgument: Int?
    
    internal init(
        name: InlineString,
        arguments: [LiquidExpression] = [],
        namedArguments: [NamedFilterArgument] = []
    ) {
        self.name = name
        self.arguments = arguments
        self.namedArguments = namedArguments
        self.builtinKind = Filter.builtinKind(for: name)
        if arguments.count == 1,
           namedArguments.isEmpty,
           case .literal(.number(let value, let isFloat)) = arguments[0],
           !isFloat,  // Only for integer literals (no decimal point in source)
           value.rounded(.towardZero) == value {
            self.singleLiteralIntegerArgument = Int(exactly: value)
        } else {
            self.singleLiteralIntegerArgument = nil
        }
    }

    internal static func builtinKind(for name: InlineString) -> BuiltinKind? {
        if name.equals("upcase") { return .upcase }
        if name.equals("downcase") { return .downcase }
        if name.equals("capitalize") { return .capitalize }
        if name.equals("size") { return .size }
        if name.equals("first") { return .first }
        if name.equals("last") { return .last }
        if name.equals("strip") { return .strip }
        if name.equals("reverse") { return .reverse }
        if name.equals("raw") { return .raw }
        if name.equals("escape") { return .escape }
        if name.equals("escape_once") { return .escapeOnce }
        if name.equals("lstrip") { return .lstrip }
        if name.equals("rstrip") { return .rstrip }
        if name.equals("abs") { return .abs }
        if name.equals("date") { return .date }
        if name.equals("json") { return .json }
        if name.equals("sum") { return .sum }
        if name.equals("uniq") { return .uniq }
        if name.equals("compact") { return .compact }
        if name.equals("slugify") { return .slugify }
        if name.equals("join") { return .join }
        if name.equals("split") { return .split }
        if name.equals("append") { return .append }
        if name.equals("prepend") { return .prepend }
        if name.equals("plus") { return .plus }
        if name.equals("minus") { return .minus }
        if name.equals("times") { return .times }
        if name.equals("divided_by") { return .dividedBy }
        if name.equals("round") { return .round }
        if name.equals("at_least") { return .atLeast }
        if name.equals("at_most") { return .atMost }
        if name.equals("map") { return .map }
        if name.equals("sort") { return .sort }
        if name.equals("limit") { return .limit }
        if name.equals("offset") { return .offset }
        if name.equals("default") { return .default }
        if name.equals("ceil") { return .ceil }
        if name.equals("floor") { return .floor }
        if name.equals("truncate") { return .truncate }
        if name.equals("truncatewords") { return .truncatewords }
        if name.equals("strip_html") { return .stripHTML }
        if name.equals("strip_newlines") { return .stripNewlines }
        if name.equals("newline_to_br") { return .newlineToBr }
        if name.equals("url_encode") { return .urlEncode }
        if name.equals("url_decode") { return .urlDecode }
        if name.equals("base64_encode") { return .base64Encode }
        if name.equals("base64_decode") { return .base64Decode }
        if name.equals("where") { return .where }
        return nil
    }
}

// MARK: - Operator Types

internal enum BinaryOp: String, Sendable, CaseIterable, Equatable {
    // Comparison operators
    case equals = "=="
    case notEquals = "!="
    case lessThan = "<"
    case greaterThan = ">"
    case lessThanOrEqual = "<="
    case greaterThanOrEqual = ">="
    
    // Logical operators
    case and = "and"
    case or = "or"
    
    // Membership operator
    case contains = "contains"
    
    // Arithmetic operators (for future extension)
    case plus = "+"
    case minus = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "%"
}

internal enum UnaryOp: String, Sendable, CaseIterable, Equatable {
    case not = "not"
    
    case negate = "-"
}

internal enum TestOp: String, Sendable, CaseIterable, Equatable {
    // Existence tests
    case defined = "defined"
    case undefined = "undefined"
    
    // Content tests
    case empty = "empty"
    case blank = "blank"
    case present = "present"
    
    // Type tests
    case number = "number"
    case string = "string"
    case array = "array"
    case boolean = "boolean"
    case object = "object"
    
    // Numeric tests
    case odd = "odd"
    case even = "even"
    case positive = "positive"
    case negative = "negative"
    case zero = "zero"
    
    // Collection tests
    case iterable = "iterable"
    case finite = "finite"
}

// MARK: - LiquidExpression Analysis and Utilities

extension LiquidExpression {
    internal var staticVariablePath: String? {
        guard let components = staticVariablePathComponents else {
            return nil
        }
        return components.joined(separator: ".")
    }

    internal var staticVariablePathComponents: [String]? {
        switch self {
        case .variable(let name):
            return name.isEmpty ? nil : [name.string]

        case .access(let expr, let key):
            guard var components = expr.staticVariablePathComponents else {
                return nil
            }

            switch key {
            case .literal(.string(let keyName)):
                guard !keyName.string.contains(".") else { return nil }
                components.append(keyName.string)
                return components
            case .literal(.number(let number, _)):
                guard number.rounded(.towardZero) == number, number >= 0 else {
                    return nil  // Negative indices need dynamic evaluation
                }
                guard let integer = Int(exactly: number) else { return nil }
                components.append(String(integer))
                return components
            default:
                return nil
            }

        default:
            return nil
        }
    }

    internal var isLiteral: Bool {
        if case .literal = self {
            return true
        }
        return false
    }
    
    internal var isVariable: Bool {
        if case .variable = self {
            return true
        }
        return false
    }
    
    internal var containsVariables: Bool {
        switch self {
        case .literal:
            return false
        case .variable:
            return true
        case .binary(let left, _, let right):
            return left.containsVariables || right.containsVariables
        case .unary(_, let expr):
            return expr.containsVariables
        case .range(let start, let end):
            return start.containsVariables || end.containsVariables
        case .filtered(let expr, let filters):
            return expr.containsVariables || filters.contains { filter in
                filter.arguments.contains { $0.containsVariables } ||
                filter.namedArguments.contains { $0.value.containsVariables }
            }
        case .test(let expr, _):
            return expr.containsVariables
        case .access(let expr, let key):
            return expr.containsVariables || key.containsVariables
        case .call(_, let arguments):
            return arguments.contains { $0.containsVariables }
        }
    }
    
    internal var referencedVariables: Set<String> {
        switch self {
        case .literal:
            return []
        case .variable(let name):
            return [name.description]
        case .binary(let left, _, let right):
            return left.referencedVariables.union(right.referencedVariables)
        case .unary(_, let expr):
            return expr.referencedVariables
        case .range(let start, let end):
            return start.referencedVariables.union(end.referencedVariables)
        case .filtered(let expr, let filters):
            var variables = expr.referencedVariables
            for filter in filters {
                for arg in filter.arguments {
                    variables.formUnion(arg.referencedVariables)
                }
                for arg in filter.namedArguments {
                    variables.formUnion(arg.value.referencedVariables)
                }
            }
            return variables
        case .test(let expr, _):
            return expr.referencedVariables
        case .access(let expr, let key):
            return expr.referencedVariables.union(key.referencedVariables)
        case .call(_, let arguments):
            return arguments.reduce(into: Set<String>()) { result, arg in
                result.formUnion(arg.referencedVariables)
            }
        }
    }
    
    internal var complexityScore: Int {
        switch self {
        case .literal:
            return 1
        case .variable:
            return 1
        case .binary(let left, _, let right):
            return left.complexityScore + right.complexityScore + 1
        case .unary(_, let expr):
            return expr.complexityScore + 1
        case .range(let start, let end):
            return start.complexityScore + end.complexityScore + 1
        case .filtered(let expr, let filters):
            let filterComplexity = filters.reduce(0) { total, filter in
                let argComplexity = filter.arguments.reduce(0) { $0 + $1.complexityScore }
                let namedArgComplexity = filter.namedArguments.reduce(0) { $0 + $1.value.complexityScore }
                return total + argComplexity + namedArgComplexity + 1
            }
            return expr.complexityScore + filterComplexity
        case .test(let expr, _):
            return expr.complexityScore + 1
        case .access(let expr, let key):
            return expr.complexityScore + key.complexityScore + 1
        case .call(_, let arguments):
            return arguments.reduce(1) { $0 + $1.complexityScore }
        }
    }
}

// MARK: - Value Utilities

extension Value {
    internal var isTruthy: Bool {
        if case .null = self { return false }
        if case .boolean(let value) = self { return value }
        return true
    }
    
    internal var isEmpty: Bool {
        switch self {
        case .special: return false
        case .null:
            return true
        case .string(let str):
            return str.isEmpty
        case .array(let arr):
            return arr.isEmpty
        case .dictionary(let dict):
            return dict.isEmpty
        case .boolean, .number, .integer:
            return false
        }
    }
    
    internal var isBlank: Bool {
        switch self {
        case .special: return true
        case .string(let str):
            return str.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return isEmpty
        }
    }
    
    internal var typeName: String {
        switch self {
        case .string: return "string"
        case .integer: return "number"
        case .number: return "number"
        case .boolean: return "boolean"
        case .null: return "null"
        case .special: return "special"
        case .array: return "array"
        case .dictionary: return "object"
        }
    }
    
    internal func toAny() -> Any {
        switch self {
        case .string(let str):
            return str.description
        case .integer(let number): return number
        case .number(let num, _):
            return num
        case .boolean(let bool):
            return bool
        case .special(let value):
            return value
        case .null:
            return NSNull()
        case .array(let arr):
            return arr.map { $0.toAny() }
        case .dictionary(let dict):
            return dict.mapValues { $0.toAny() }
        }
    }
    
    internal static func from(_ any: Any) -> Value {
        switch any {
        case let str as String:
            return .string(InlineString(str))
        case let num as Double:
            return .number(num)
        case let num as Int:
            return .number(Double(num))
        case let num as Float:
            return .number(Double(num))
        case let bool as Bool:
            return .boolean(bool)
        case is NSNull:
            return .null
        case let arr as [Any]:
            return .array(arr.map { Value.from($0) })
        case let dict as [String: Any]:
            return .dictionary(dict.mapValues { Value.from($0) })
        default:
            return .string(InlineString(String(describing: any)))
        }
    }
}

// MARK: - Operator Utilities

extension BinaryOp {
    internal var precedence: Int {
        switch self {
        case .multiply, .divide, .modulo:
            return 6
        case .plus, .minus:
            return 5
        case .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
            return 4
        case .equals, .notEquals:
            return 3
        case .contains:
            return 3
        case .and:
            return 2
        case .or:
            return 1
        }
    }
    
    internal var isLeftAssociative: Bool {
        return true // All current operators are left-associative
    }
    
    internal var isComparison: Bool {
        switch self {
        case .equals, .notEquals, .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual:
            return true
        default:
            return false
        }
    }
    
    internal var isLogical: Bool {
        switch self {
        case .and, .or:
            return true
        default:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension LiquidExpression: CustomStringConvertible {
    internal var description: String {
        switch self {
        case .literal(let value):
            return value.description
        case .variable(let name):
            return name.description
        case .binary(let left, let op, let right):
            return "(\(left) \(op.rawValue) \(right))"
        case .unary(let op, let expr):
            return "\(op.rawValue)(\(expr))"
        case .range(let start, let end):
            return "(\(start)..\(end))"
        case .filtered(let expr, let filters):
            let filterString = filters.map { "| \($0.name)" }.joined(separator: " ")
            return "\(expr) \(filterString)"
        case .test(let expr, let test):
            return "\(expr) is \(test.rawValue)"
        case .access(let expr, let key):
            return "\(expr)[\(key)]"
        case .call(let name, let arguments):
            let argString = arguments.map { $0.description }.joined(separator: ", ")
            return "\(name)(\(argString))"
        }
    }
}

extension CallArgument: CustomStringConvertible {
    internal var description: String {
        if let label {
            return "\(label): \(value)"
        }
        return value.description
    }
}

extension Value: CustomStringConvertible {
    internal var description: String {
        switch self {
        case .string(let str):
            return "\"\(str)\""
        case .integer(let number): return String(number)
        case .number(let num, _):
            return String(num)
        case .boolean(let bool):
            return String(bool)
        case .special(let value):
            return value.rawValue
        case .null:
            return "null"
        case .array(let arr):
            let elements = arr.map { $0.description }.joined(separator: ", ")
            return "[\(elements)]"
        case .dictionary(let dict):
            let pairs = dict.map { "\($0.key): \($0.value.description)" }.joined(separator: ", ")
            return "{\(pairs)}"
        }
    }
}

extension Filter: CustomStringConvertible {
    internal var description: String {
        if arguments.isEmpty && namedArguments.isEmpty {
            return name.description
        }
        
        var argStrings: [String] = []
        argStrings.append(contentsOf: arguments.map { $0.description })
        argStrings.append(contentsOf: namedArguments.map { "\($0.name): \($0.value.description)" })
        
        return "\(name): \(argStrings.joined(separator: ", "))"
    }
}

extension Value {
    var parameterInteger: Int? {
        switch self {
        case .integer(let value): return value
        case .number(let value, _): return Int(exactly: value.rounded(.towardZero))
        default: return nil
        }
    }
}
