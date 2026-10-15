// SPDX-License-Identifier: Apache-2.0
import Foundation

private enum ImmediateLeaf: Sendable {
    case text(InlineString)
    case variable(InlineString)

    init?(_ node: ASTNode) {
        switch node {
        case .text(let text), .raw(let text): self = .text(text)
        case .output(.variable(let name), _), .echo(.variable(let name), _): self = .variable(name)
        default: return nil
        }
    }

    var staticBytes: Int {
        if case .text(let text) = self { return text.utf8Count }
        return 0
    }
}

private enum ImmediateTemplatePlan: Sendable {
    case empty
    case single(ImmediateLeaf)
    case pair(ImmediateLeaf, ImmediateLeaf)
    case triple(ImmediateLeaf, ImmediateLeaf, ImmediateLeaf)

    init?(_ node: ASTNode) {
        guard case .template(let nodes) = node else { return nil }
        // Classify the whole bounded shape before evaluating or charging anything.
        switch nodes.count {
        case 0: self = .empty
        case 1:
            guard let first = ImmediateLeaf(nodes[0]) else { return nil }
            self = .single(first)
        case 2:
            guard let first = ImmediateLeaf(nodes[0]), let second = ImmediateLeaf(nodes[1]) else { return nil }
            self = .pair(first, second)
        case 3:
            guard let first = ImmediateLeaf(nodes[0]), let second = ImmediateLeaf(nodes[1]),
                  let third = ImmediateLeaf(nodes[2]) else { return nil }
            self = .triple(first, second, third)
        default: return nil
        }
    }
}

extension Renderer {
    /// Avoids asynchronous node calls for small roots that cannot suspend or recover errors.
    /// Each root/leaf retains its original enter, output, depth and cancellation boundaries.
    internal func renderImmediateTemplate(_ node: ASTNode) throws -> String? {
        guard let plan = ImmediateTemplatePlan(node) else { return nil }
        try budget.enter()
        defer { budget.activeDepth -= 1 }
        let output: String
        switch plan {
        case .empty: output = ""
        case .single(let leaf): output = try renderImmediateLeaf(leaf)
        case .pair(let first, let second):
            var buffer = String()
            let capacity = first.staticBytes + second.staticBytes
            if capacity > 0 { buffer.reserveCapacity(capacity) }
            try appendImmediateLeaf(first, to: &buffer)
            try appendImmediateLeaf(second, to: &buffer)
            output = buffer
        case .triple(let first, let second, let third):
            var buffer = String()
            let capacity = first.staticBytes + second.staticBytes + third.staticBytes
            if capacity > 0 { buffer.reserveCapacity(capacity) }
            try appendImmediateLeaf(first, to: &buffer)
            try appendImmediateLeaf(second, to: &buffer)
            try appendImmediateLeaf(third, to: &buffer)
            output = buffer
        }
        try budget.output(output)
        return output
    }

    private func renderImmediateLeaf(_ leaf: ImmediateLeaf) throws -> String {
        try budget.enter()
        defer { budget.activeDepth -= 1 }
        let output: String
        switch leaf {
        case .text(let text): output = text.string
        case .variable(let name): output = stringify(context.getVariable(name.string) ?? NSNull())
        }
        try budget.output(output)
        return output
    }

    private func appendImmediateLeaf(_ leaf: ImmediateLeaf, to output: inout String) throws {
        // The general multi-node template loop checks here before entering each child.
        try Task.checkCancellation()
        output.append(try renderImmediateLeaf(leaf))
    }
}
