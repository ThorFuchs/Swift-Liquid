// SPDX-License-Identifier: Apache-2.0
import Testing

// Isolated runner-admission probes deliberately fail or skip. Never part of LiquidTests.
@Test(arguments: [1, 2]) func passing(_ value: Int) { #expect(value > 0) }
@Test(.disabled("Deliberate evidence probe")) func disabled() { }
@Test func failing() { Issue.record("Deliberate evidence probe") }
@Test func known() { withKnownIssue { Issue.record("Deliberate evidence probe") } }
@Test(arguments: [Int]()) func empty(_ value: Int) { #expect(value > 0) }
@Test(arguments: [1, 2]) func caseFailure(_ value: Int) { #expect(value == 1) }
