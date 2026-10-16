// SPDX-License-Identifier: Apache-2.0
import Foundation

// Internal byte provenance is independent of any future editor/UTF-16 view.
internal enum DiagnosticSourceIdentity: Sendable, Equatable {
    case anonymous
    case root
    case partial(ScalarKey)
}

internal enum DiagnosticSourceProvenance: Sendable, Equatable {
    case original(DiagnosticSourceIdentity)
    case unmapped
}

internal enum DiagnosticOriginGap: Sendable, Equatable {
    case unspecifiedOrRewrittenSource
    case invalidBoundary
    case reasonDoesNotMatchOriginalScalar
    case incompleteOrAmbiguousConstruct
    case liquidInnerContext
}

internal enum DiagnosticOriginResolution: Sendable, Equatable {
    case resolved(DiagnosticSourceOrigin)
    case unmapped(DiagnosticOriginGap)
}

internal struct DiagnosticSourcePosition: Sendable, Equatable {
    let line: Int
    let column: Int
}

internal struct DiagnosticSourceOrigin: Sendable, Equatable {
    let sourceIdentity: DiagnosticSourceIdentity
    let construct: Range<Int>
    let markup: Range<Int>
    let offending: Range<Int>
    let anchor: Int
    let position: DiagnosticSourcePosition
    let contextText: String
    let presentation: DiagnosticContextPresentation

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sourceIdentity == rhs.sourceIdentity && lhs.construct == rhs.construct &&
            lhs.markup == rhs.markup && lhs.offending == rhs.offending && lhs.anchor == rhs.anchor &&
            lhs.position == rhs.position && lhs.presentation == rhs.presentation &&
            lhs.contextText.utf8.elementsEqual(rhs.contextText.utf8)
    }
}

internal enum DiagnosticContextPresentation: Sendable, Equatable {
    case markup
    case outputMarkup
    case reasonOnly
}

// The producer supplies candidate presentation ranges after native rejection.
// The byte owner validates them; it never recognizes tags or selects delimiters.
internal struct DiagnosticSourceFrame: Sendable {
    let construct: Range<Int>
    let markup: Range<Int>
    let anchor: Int
    let presentation: DiagnosticContextPresentation
    let header: Range<Int>?
    let headerSpelling: String?
}

// The single original-byte authority validates supplied spans and provides the
// LF/scalar engine view. It never searches delimiters, recognizes tags or emits AST.
internal struct DiagnosticSourceSnapshot: Sendable {
    private let bytes: [UInt8]
    let identity: DiagnosticSourceIdentity

    // The lexer owns this UTF-8 buffer, originally created from an admitted String.
    init(admittedUTF8 bytes: [UInt8], identity: DiagnosticSourceIdentity) {
        self.bytes = bytes
        self.identity = identity
    }

    func isBoundary(_ offset: Int) -> Bool {
        offset >= 0 && offset <= bytes.count &&
            (offset == bytes.count || bytes[offset] & 0xC0 != 0x80)
    }

    func position(at offset: Int) throws -> DiagnosticSourcePosition? {
        try Task.checkCancellation()
        guard isBoundary(offset) else { return nil }
        var line = 1
        var column = 1
        for index in 0..<offset {
            if index & 255 == 0 { try Task.checkCancellation() }
            if bytes[index] == 10 {
                line += 1
                column = 1
            } else if bytes[index] & 0xC0 != 0x80 {
                column += 1
            }
        }
        return .init(line: line, column: column)
    }

    func unexpectedCharacter(_ character: Character, at offset: Int,
                             frame: DiagnosticSourceFrame) throws -> DiagnosticOriginResolution {
        try Task.checkCancellation()
        guard valid(frame.construct), valid(frame.markup), isBoundary(frame.anchor), isBoundary(offset),
              offset < bytes.count, frame.construct.lowerBound <= frame.markup.lowerBound,
              frame.markup.upperBound <= frame.construct.upperBound,
              frame.markup.lowerBound <= offset, frame.construct.lowerBound <= frame.anchor,
              frame.anchor <= offset else {
            return .unmapped(.invalidBoundary)
        }
        guard (frame.header == nil) == (frame.headerSpelling == nil) else { return .unmapped(.invalidBoundary) }
        if let header = frame.header {
            guard valid(header), header.lowerBound >= frame.construct.lowerBound, header.upperBound <= frame.markup.lowerBound,
                  let spelling = frame.headerSpelling,
                  bytes[header].elementsEqual(spelling.utf8) else { return .unmapped(.invalidBoundary) }
        }
        let spelling = Array(character.utf8)
        guard spelling.count <= bytes.count - offset, isBoundary(offset + spelling.count),
              bytes[offset..<(offset + spelling.count)].elementsEqual(spelling) else {
            return .unmapped(.reasonDoesNotMatchOriginalScalar)
        }
        guard offset + spelling.count <= frame.markup.upperBound,
              let position = try position(at: frame.anchor) else {
            return .unmapped(.invalidBoundary)
        }
        let context = String(decoding: bytes[frame.markup], as: UTF8.self)
        try Task.checkCancellation()
        return .resolved(.init(sourceIdentity: identity,
            construct: frame.construct, markup: frame.markup,
            offending: offset..<(offset + spelling.count), anchor: frame.anchor,
            position: position, contextText: context, presentation: frame.presentation))
    }

    private func valid(_ range: Range<Int>) -> Bool {
        isBoundary(range.lowerBound) && isBoundary(range.upperBound)
    }
}
