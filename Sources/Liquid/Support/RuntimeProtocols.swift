// SPDX-License-Identifier: Apache-2.0
internal protocol CustomFilter: Sendable {
    var name: String { get }
    func apply(to value: Any, arguments: [Any], namedArguments: [String: Any]) async throws -> Any
}
