// SPDX-License-Identifier: Apache-2.0
import Testing
import Liquid

@Test func rendersGreeting() async throws {
    let output = try await LiquidEngine().render(template: "Hello, {{ name | upcase }}!", context: ["name": "Swift"])
    #expect(output == "Hello, SWIFT!")
}
