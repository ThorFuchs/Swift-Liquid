// SPDX-License-Identifier: Apache-2.0
// Adapted from RhoeLiquid; Copyright 2024-2026 Thor Fuchs.
// Modified for Swift-Liquid: internal runtime, standard dialect, invocation-owned state.
//
//  Renderer+Expressions.swift
//  LiquidRenderer
//
//

import Foundation

extension Renderer {
    // MARK: - LiquidExpression Evaluation
    
    internal func renderExpression(_ expression: LiquidExpression) async throws -> String {
        return try await renderExpressionFast(expression)
    }

    @inline(__always)
    internal func renderExpressionFast(_ expression: LiquidExpression) async throws -> String {
        switch expression {
        case .literal(let value):
            return stringify(try evaluateValue(value))
        case .variable(let name):
            return stringify(context.getVariable(name.string) ?? NSNull())
        case .access:
            if let path = expression.staticVariablePath {
                return stringify(context.getVariable(path) ?? NSNull())
            }
            return stringify(try await evaluateExpressionFast(expression))
        case .filtered(let expr, let filters):
            let baseValue = try await evaluateFilteredBaseValueFast(expr)
            let renderedValue = try await evaluateFilteredValue(baseValue: baseValue, filters: filters)
            return stringify(renderedValue)
        default:
            return stringify(try await evaluateExpressionFast(expression))
        }
    }

    @inline(__always)


    
    internal func evaluateExpression(_ expression: LiquidExpression) async throws -> Any {
        return try await evaluateExpressionFast(expression)
    }

    internal func evaluateExpressionFast(_ expression: LiquidExpression) async throws -> Any {
        try budget.step()
        switch expression {
        case .literal(let value):
            return try evaluateValue(value)

        case .variable(let name):
            return context.getVariable(name.string) ?? NSNull()

        case .access(let expr, let key, let command):
            if let path = expression.staticVariablePath {
                return context.getVariable(path) ?? NSNull()
            }
            // Handle bracket notation sentinel: .access(.variable(""), key)
            // [expr] means indirect lookup: evaluate expr, use result as variable name
            if case .variable(let name) = expr, name.string.isEmpty {
                let keyValue = try await evaluateExpressionFast(key)
                let varName = stringify(keyValue)
                return context.getLiteralVariable(varName) ?? NSNull()
            }
            let baseValue = try await evaluateExpressionFast(expr)
            switch key {
            case .literal(.string(let keyName)):
                return evaluateAccessValueWithStringKey(baseValue: baseValue, key: keyName.string, command: command)
            case .literal(.number(let number, _)):
                return evaluateAccessValueWithIndex(baseValue: baseValue, index: integerValue(number) ?? Int.max)
            default:
                let keyValue = try await evaluateExpressionFast(key)
                return try await evaluateAccessValueWithKey(baseValue: baseValue, keyValue: keyValue)
            }

        case .filtered(let expr, let filters):
            let baseValue = try await evaluateFilteredBaseValueFast(expr)
            return try await evaluateFilteredValue(baseValue: baseValue, filters: filters)

        case .binary(let left, let op, let right):
            let leftValue = try await evaluateExpressionFast(left)
            let rightValue = try await evaluateExpressionFast(right)
            return try await evaluateBinaryValues(leftValue: leftValue, op: op, rightValue: rightValue)

        case .unary(let op, let expr):
            let exprValue = try await evaluateExpressionFast(expr)
            return try await evaluateUnaryValue(op: op, value: exprValue)

        case .range(let start, let end):
            return try await evaluateRange(start: start, end: end)

        case .test(let expr, let test):
            let exprValue = try await evaluateExpressionFast(expr)
            return try await evaluateTestValue(exprValue: exprValue, test: test)

        case .call(let name, let arguments):
            return try await evaluateCall(name: name, arguments: arguments, fast: true)
        }
    }




    
    internal func evaluateValue(_ value: Value) throws -> Any {
        switch value {
        case .string(let str):
            return str.string
        case .number(let num, let isFloat):
            // Use source literal info to distinguish Int (5) from Float (5.0)
            if isFloat {
                return num  // Keep as Double — source had decimal point
            }
            // Integer literal — convert to Int for proper stringification
            if num == floor(num), !num.isInfinite, !num.isNaN,
               num >= Double(Int.min), num < Double(Int.max) {
                return Int(num)
            }
            return num
        case .integer(let value): return value
        case .boolean(let bool):
            return bool
        case .special(let value):
            return value
        case .null:
            return NSNull()
        case .array(let values):
            return try values.map { try evaluateValue($0) }
        case .dictionary(let dict):
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = try evaluateValue(val)
            }
            return result
        }
    }
    
    internal func evaluateAccess(expr: LiquidExpression, key: LiquidExpression) async throws -> Any {
        let object = try await evaluateExpression(expr)
        let keyValue = try await evaluateExpression(key)
        return try await evaluateAccessValueWithKey(baseValue: object, keyValue: keyValue)
    }
    
    internal func evaluateAccessValue(baseValue: Any, key: LiquidExpression) async throws -> Any {
        switch key {
        case .literal(.string(let keyName)):
            return evaluateAccessValueWithStringKey(baseValue: baseValue, key: keyName.string)
        case .literal(.number(let number, _)):
            return evaluateAccessValueWithIndex(baseValue: baseValue, index: integerValue(number) ?? Int.max)
        default:
            let keyValue = try await evaluateExpression(key)
            return try await evaluateAccessValueWithKey(baseValue: baseValue, keyValue: keyValue)
        }
    }
    
    internal func evaluateAccessValueWithKey(baseValue: Any, keyValue: Any) async throws -> Any {
        if let index = keyValue as? Int {
            return evaluateAccessValueWithIndex(baseValue: baseValue, index: index)
        }
        if let index = keyValue as? Double {
            return evaluateAccessValueWithIndex(baseValue: baseValue, index: integerValue(index) ?? Int.max)
        }
        if let key = keyValue as? String {
            return evaluateAccessValueWithStringKey(baseValue: baseValue, key: key)
        }
        if let key = keyValue as? InlineString {
            return evaluateAccessValueWithStringKey(baseValue: baseValue, key: key.string)
        }
        if let key = keyValue as? SafeHTML {
            return evaluateAccessValueWithStringKey(baseValue: baseValue, key: key.value)
        }

        return evaluateAccessValueWithStringKey(baseValue: baseValue, key: stringify(keyValue))
    }

    @inline(__always)
    internal func evaluateAccessValueWithIndex(baseValue: Any, index: Int) -> Any {
        guard let array = baseValue as? [Any] else {
            return NSNull()
        }
        // Support negative indexing (Shopify behavior: a[-1] is last element)
        let resolvedIndex = index < 0 ? array.count + index : index
        guard resolvedIndex >= 0 && resolvedIndex < array.count else {
            return NSNull()
        }
        return array[resolvedIndex]
    }

    @inline(__always)
    internal func evaluateAccessValueWithStringKey(baseValue: Any, key: String, command: Bool = false) -> Any {
        if let range = baseValue as? RuntimeRange {
            guard command, let value = range.commandValue(for: key) else { return NSNull() }
            return value
        }
        // Dictionary lookup takes priority — enables forloop.first, forloop.last, forloop.length
        if let val = dictValue(baseValue, forKey: key) { return val }
        if isDictLike(baseValue) { /* key not found, fall through */ }
        if key == "size" {
            return command ? runtimeSizeProperty(baseValue) ?? NSNull() : NSNull()
        }
        if key == "length" { return NSNull() }
        if key == "first" {
            if let array = baseValue as? [Any], !array.isEmpty {
                return array[0]
            }
            if let pairs = orderedDictPairs(baseValue), let first = pairs.first {
                return [first.0, first.1] as [Any]
            }
            return NSNull()
        }
        if key == "last" {
            if let array = baseValue as? [Any], !array.isEmpty {
                return array[array.count - 1]
            }
            // Note: .last is NOT supported for hashes in Shopify Liquid (only .first is)
            return NSNull()
        }

        let mirror = Mirror(reflecting: baseValue)
        for child in mirror.children {
            if child.label == key {
                return child.value
            }
        }
        return ""
    }
    
    internal func evaluateFiltered(expr: LiquidExpression, filters: [Filter]) async throws -> Any {
        let value = try await evaluateExpression(expr)
        return try await evaluateFilteredValue(baseValue: value, filters: filters)
    }

    @inline(__always)
    internal func evaluateFilteredBaseValueFast(_ expression: LiquidExpression) async throws -> Any {
        switch expression {
        case .literal(let value):
            return try evaluateValue(value)
        case .variable(let name):
            return context.getVariable(name.string) ?? NSNull()
        case .access:
            if let path = expression.staticVariablePath {
                return context.getVariable(path) ?? NSNull()
            }
            return try await evaluateExpressionFast(expression)
        default:
            return try await evaluateExpressionFast(expression)
        }
    }
    
    internal func evaluateFilteredValue(baseValue: Any, filters: [Filter]) async throws -> Any {
        return try await evaluateFilteredValueFast(baseValue: baseValue, filters: filters)
    }

    @inline(__always)
    internal func evaluateFilteredValueFast(baseValue: Any, filters: [Filter]) async throws -> Any {
        switch filters.count {
        case 0:
            return baseValue
        case 1:
            return try await applyFilterFast(filters[0], to: baseValue)
        default:
            var value = baseValue
            for filter in filters {
                value = try await applyFilterFast(filter, to: value)
            }
            return value
        }
    }
    
    internal func evaluateBinary(left: LiquidExpression, op: BinaryOp, right: LiquidExpression) async throws -> Any {
        let leftValue = try await evaluateExpression(left)
        let rightValue = try await evaluateExpression(right)
        return try await evaluateBinaryValues(leftValue: leftValue, op: op, rightValue: rightValue)
    }
    
    internal func evaluateBinaryValues(leftValue: Any, op: BinaryOp, rightValue: Any) async throws -> Any {
        switch op {
        case .equals:
            return isEqual(leftValue, rightValue)
        case .notEquals:
            return !isEqual(leftValue, rightValue)
        case .lessThan:
            return try isLess(leftValue, rightValue)
        case .lessThanOrEqual:
            return try isLessEqual(leftValue, rightValue)
        case .greaterThan:
            return try isGreater(leftValue, rightValue)
        case .greaterThanOrEqual:
            return try isGreaterEqual(leftValue, rightValue)
        case .and:
            return isTruthy(leftValue) && isTruthy(rightValue)
        case .or:
            return isTruthy(leftValue) || isTruthy(rightValue)
        case .contains:
            return contains(leftValue, rightValue)
        case .plus:
            return try add(leftValue, rightValue)
        case .minus:
            return try subtract(leftValue, rightValue)
        case .multiply:
            return try multiply(leftValue, rightValue)
        case .divide:
            return try divide(leftValue, rightValue)
        case .modulo:
            return try modulo(leftValue, rightValue)
        }
    }
    
    internal func evaluateUnary(op: UnaryOp, expr: LiquidExpression) async throws -> Any {
        let value = try await evaluateExpression(expr)
        return try await evaluateUnaryValue(op: op, value: value)
    }
    
    internal func evaluateUnaryValue(op: UnaryOp, value: Any) async throws -> Any {
        switch op {
        case .not:
            return !isTruthy(value)
        case .negate:
            guard let num = value as? Double else {
                throw RenderError.typeError(expected: "number", actual: "\(type(of: value))", operation: "negation")
            }
            return -num
        }
    }
    
    internal func evaluateRange(start: LiquidExpression, end: LiquidExpression) async throws -> Any {
        let startValue = try await evaluateExpression(start)
        let endValue = try await evaluateExpression(end)
        if startValue is Double, case .literal = start {} else if startValue is Double {
            throw RenderError.custom("Range bounds from variables must be integers")
        }
        if endValue is Double, case .literal = end {} else if endValue is Double {
            throw RenderError.custom("Range bounds from variables must be integers")
        }
        return try await evaluateRangeValues(startValue: startValue, endValue: endValue)
    }
    
    internal func evaluateRangeValues(startValue: Any, endValue: Any) async throws -> Any {
        // Coerce to numeric: non-numeric strings → 0, nil → 0
        let startNum = numericValue(startValue) ?? 0
        let endNum = numericValue(endValue)

        // If end is not a number (e.g., "foo"), return empty array
        guard let endNum else {
            return [Any]()
        }

        guard let startInt = Int(exactly: startNum.rounded(.towardZero)),
              let endInt = Int(exactly: endNum.rounded(.towardZero)) else { throw RenderError.custom("Range bound exceeds integer range") }

        if startInt > endInt {
            return RuntimeRange(start: startInt, end: endInt, count: 0)
        }
        let (distance, overflow) = endInt.subtractingReportingOverflow(startInt)
        guard !overflow, distance < budget.limits.loopIterations else { throw RenderError.custom("Range exceeds iteration limit") }
        return RuntimeRange(start: startInt, end: endInt, count: distance + 1)
    }
    
    internal func evaluateTest(expr: LiquidExpression, test: TestOp) async throws -> Any {
        let value = try await evaluateExpression(expr)
        return try await evaluateTestValue(exprValue: value, test: test)
    }
    
    internal func evaluateTestValue(exprValue: Any, test: TestOp) async throws -> Any {
        switch test {
        case .defined:
            return !(exprValue is NSNull) && exprValue as? String != ""
        case .undefined:
            return (exprValue is NSNull) || exprValue as? String == ""
        case .empty:
            return isEmpty(exprValue)
        case .blank:
            return isBlank(exprValue)
        case .present:
            return !isEmpty(exprValue)
        case .number:
            return exprValue is Double
        case .string:
            return exprValue is String
        case .array:
            return exprValue is [Any]
        case .boolean:
            return exprValue is Bool
        case .object:
            return exprValue is [String: Any] || exprValue is RuntimeObject
        case .odd:
            guard let num = exprValue as? Double else { return false }
            return Int(num) % 2 == 1
        case .even:
            guard let num = exprValue as? Double else { return false }
            return Int(num) % 2 == 0
        case .positive:
            guard let num = exprValue as? Double else { return false }
            return num > 0
        case .negative:
            guard let num = exprValue as? Double else { return false }
            return num < 0
        case .zero:
            guard let num = exprValue as? Double else { return false }
            return num == 0
        case .iterable:
            return exprValue is [Any] || exprValue is String
        case .finite:
            guard let num = exprValue as? Double else { return false }
            return num.isFinite
        }
    }
    
    internal func evaluateCall(
        name: InlineString,
        arguments: [CallArgument],
        fast: Bool
    ) async throws -> Any {
        throw RenderError.custom("Function calls are not part of standard Liquid")
    }
    

}
