// SPDX-License-Identifier: Apache-2.0
import Foundation
import JSON
import JSONSchema

// Operational failures propagate; they are never counted as negative validation verdicts.
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3 else { fatalError("Usage: LiquidSchemaQualification SCHEMA (valid|invalid) INSTANCE ...") }
guard arguments.count % 2 == 1 else { fatalError("Expected verdict/path pairs") }
let parser = JSONParser()
let schema = try JSONSchemaDocument(parser.parse(Data(contentsOf: URL(fileURLWithPath: arguments[0]))))
let plan = try JSONSchemaCompiler().compile(schema)
let validator = JSONSchemaValidator()
var positive = 0, negative = 0
for offset in stride(from: 1, to: arguments.count, by: 2) {
    let expected = arguments[offset]
    guard expected == "valid" || expected == "invalid" else { fatalError("Unknown verdict") }
    let instance = try parser.parse(Data(contentsOf: URL(fileURLWithPath: arguments[offset + 1])))
    let result = try validator.validate(instance, against: plan)
    guard result.isValid == (expected == "valid") else { fatalError("Schema verdict mismatch for " + arguments[offset + 1]) }
    if result.isValid { positive += 1 } else { negative += 1 }
}
print("Swift-JSON 1.3.0 JSONSchema: \(positive) positive and \(negative) negative dependency-report cases passed.")
