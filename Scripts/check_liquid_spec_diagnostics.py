#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Negative controls for explanatory classification and immutable raw verdicts."""
from copy import deepcopy
import unittest
from analyze_liquid_spec import audit, indexed
from liquid_spec_diagnostics import dimensions


def row():
    return {'caseID': 'suite/source:1/case/strict2/raise', 'suite': 'parser_errors', 'case': 'case',
            'parserMode': 'strict2', 'renderMode': 'raise', 'featureTags': [], 'reason': 'portable',
            'sourceLocation': {'file': 'source', 'line': 1}, 'sourceDigest': 'source', 'resultDigest': 'result',
            'selected': True, 'comparison': 'mismatched', 'qualificationComparison': 'mismatched',
            'upstreamVerdict': {'passed': False}, 'referenceQualificationComparison': 'matched',
            'compileOutcome': 'parse-error', 'expectedCategory': 'parse-error', 'observedCategory': 'parse-error',
            'expectation': {'errors': {'line': 2}},
            'reportedErrors': {'type': 'syntax_error', 'message': 'Expected ] but found identifier(x)', 'line': 2, 'column': 4},
            'referenceReportedErrors': {'type': 'Liquid::SyntaxError', 'message': 'Expected close_square but found id', 'line': 2},
            'diagnosticEvidence': {'messagePatternsMatch': False, 'locationMatch': True}}


class EvidenceTests(unittest.TestCase):
    def test_same_explicit_condition_is_not_a_comparator_pass(self):
        r = row(); value = audit([r])
        self.assertEqual(value['rows'][0]['dimensions']['reasonEquivalence'], 'same-reference-condition')
        self.assertEqual(value['summary']['qualificationComparisons'], {'mismatched': 1})

    def test_different_expected_token_remains_different(self):
        r = row(); r['reportedErrors']['message'] = 'Expected ) but found identifier(x)'
        self.assertEqual(dimensions(r)['reasonEquivalence'], 'different-reference-condition')

    def test_generic_error_does_not_establish_equivalence(self):
        r = row(); r['reportedErrors']['message'] = 'Unexpected token: identifier(x)'
        self.assertEqual(dimensions(r)['reasonEquivalence'], 'not-established')

    def test_span_requires_matching_patterns_and_failed_upstream_location(self):
        r = row(); r['diagnosticEvidence'] = {'messagePatternsMatch': True, 'locationMatch': False}
        self.assertEqual(dimensions(r)['diagnosticClassification'], 'span-requirement')
        r['diagnosticEvidence']['messagePatternsMatch'] = False
        self.assertNotEqual(dimensions(r)['diagnosticClassification'], 'span-requirement')

    def test_raw_default_pass_can_still_fail_phase(self):
        r = row(); r.update(comparison='matched', upstreamVerdict={'passed': True}, observedCategory='successful-render', compileOutcome='compiled')
        value = audit([r]); self.assertEqual(value['summary']['rawPassWithQualificationFailure'], 1)
        self.assertFalse(dimensions(r)['phaseCompatible'])

    def test_recovered_output_is_not_error_free(self):
        r = row(); r.update(expectedCategory='output', observedCategory='recovered-error', renderedOutput='é', compileOutcome='compiled')
        d = dimensions(r); self.assertTrue(d['phaseCompatible']); self.assertFalse(d['errorFreeRender'])
        self.assertEqual(d['renderedBytes'], 2); self.assertEqual(d['recoveredOutput'], 'é')

    def test_failed_compile_operation_is_unknown_acceptance(self):
        r = row(); r.update(observedCategory='operational-error', compileOutcome='attempted')
        self.assertIsNone(dimensions(r)['parseAcceptance'])

    def test_duplicate_id_or_source_identity_rejected(self):
        r = row()
        with self.assertRaises(ValueError): indexed([r, deepcopy(r)])
        other = deepcopy(r); other['caseID'] = 'other'
        with self.assertRaises(ValueError): indexed([r, other])

    def test_raw_verdict_override_or_promoted_failure_rejected(self):
        r = row(); r['comparison'] = 'matched'
        with self.assertRaises(ValueError): audit([r])
        r = row(); r['qualificationComparison'] = 'matched'
        with self.assertRaises(ValueError): audit([r])

    def test_changed_eligibility_or_expectation_rejected(self):
        original = row(); changed = deepcopy(original); changed['selected'] = False
        with self.assertRaises(ValueError): audit([changed], [original])
        changed = deepcopy(original); changed['expectation']['errors']['line'] = 99
        with self.assertRaises(ValueError): audit([changed], [original])


if __name__ == '__main__':
    unittest.main()
