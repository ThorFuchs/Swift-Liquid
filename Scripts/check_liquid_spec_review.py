#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Regression checks for the reviewed-conflict boundary."""
from copy import deepcopy
import json
import unittest

from review_liquid_spec import POLICY, eligibility_digest, evaluate


def examples():
    policy = json.loads(POLICY.read_text())
    rows = []
    for index, item in enumerate(policy['conflicts']):
        row = deepcopy(item)
        row.update(suite='test', case='conflict-' + str(index), sourceLocation={'file': 'fixture', 'line': index},
                   selected=True, reason='selected', featureTags=[], resultDigest='evidence',
                   comparison='mismatched', qualificationComparison='mismatched',
                   referenceComparison='mismatched', referenceQualificationComparison='mismatched',
                   upstreamVerdict={'passed': False}, referenceUpstreamVerdict={'passed': False})
        rows.append(row)
    matched = deepcopy(rows[0]); matched.update(caseID='matched', case='matched', sourceLocation={'file': 'fixture', 'line': 6},
        comparison='matched', qualificationComparison='matched', upstreamVerdict={'passed': True},
        referenceQualificationComparison='matched')
    excluded = deepcopy(matched); excluded.update(caseID='excluded', case='excluded', sourceLocation={'file': 'fixture', 'line': 7},
        selected=False, reason='transport-inapplicable: test', observedCategory='transport-inapplicable',
        comparison='not-executed', qualificationComparison='not-executed')
    rows.extend([matched, excluded])
    policy['expectedPopulation'] = len(rows)
    policy['eligibilitySHA256'] = eligibility_digest(rows)
    return rows, policy


class ReviewTests(unittest.TestCase):
    def test_expected_conflicts_remain_raw_failures(self):
        rows, policy = examples()
        result = evaluate(rows, policy)
        self.assertEqual((result['matched'], result['reviewedConflicts'], result['notExecuted'], result['unexpectedFailures']), (1, 5, 1, 0))
        self.assertEqual(result['rawStatus'], 'failed')
        self.assertTrue(all(row['comparison'] == 'mismatched' for row in rows[:5]))

    def test_changed_conflict_or_reference_is_not_waived(self):
        for key in ('actual', 'referenceActual', 'semanticResultDigest'):
            rows, policy = examples(); rows[0][key] = 'changed'
            with self.assertRaises(ValueError): evaluate(rows, policy)
        rows, policy = examples(); rows[0]['referenceUpstreamVerdict']['passed'] = True
        with self.assertRaises(ValueError): evaluate(rows, policy)

    def test_new_failure_and_stale_passing_exception_fail(self):
        rows, policy = examples(); rows[-2].update(comparison='mismatched', qualificationComparison='mismatched', upstreamVerdict={'passed': False})
        with self.assertRaises(ValueError): evaluate(rows, policy)
        rows, policy = examples(); rows[0].update(comparison='matched', qualificationComparison='matched', upstreamVerdict={'passed': True})
        with self.assertRaises(ValueError): evaluate(rows, policy)

    def test_eligibility_change_and_hidden_operation_fail(self):
        rows, policy = examples(); rows[-1]['reason'] = 'different'
        with self.assertRaises(ValueError): evaluate(rows, policy)
        rows, policy = examples(); rows[-1]['observedCategory'] = 'operational-error'
        with self.assertRaises(ValueError): evaluate(rows, policy)

    def test_duplicates_and_changed_fixture_fail(self):
        rows, policy = examples(); rows.append(deepcopy(rows[0]))
        with self.assertRaises(ValueError): evaluate(rows, policy)
        rows, policy = examples(); rows[0]['sourceDigest'] = 'changed'
        with self.assertRaises(ValueError): evaluate(rows, policy)


if __name__ == '__main__':
    unittest.main()
