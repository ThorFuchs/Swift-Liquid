#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Regression checks for the reviewed-conflict boundary."""
from copy import deepcopy
import json
import unittest

from review_liquid_spec import (POLICY, GENERATOR_EVIDENCE, DROP_EVIDENCE, eligibility_digest,
                                historical_eligibility_digest, project_standard_drop_admissions,
                                check_generator_preparation, evaluate)


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

    def test_deferred_generators_only_project_historical_metadata(self):
        rows, policy = examples()
        evidence = json.loads(GENERATOR_EVIDENCE.read_text())
        for item in evidence['cases']:
            row = deepcopy(rows[-1])
            row.update(caseID=item['caseID'], sourceDigest=item['sourceDigest'],
                       sourceLocation={'file': 'drops', 'line': len(rows)},
                       expectation={'output': item['expression'], 'outputPattern': None, 'errors': {}},
                       expectationMaterialization='deferred-excluded-generator')
            rows.append(row)
        original = deepcopy(rows)
        policy['expectedPopulation'] = len(rows)
        policy['eligibilitySHA256'] = historical_eligibility_digest(rows, policy)[0]
        result = evaluate(rows, policy)
        self.assertEqual(rows, original)
        self.assertEqual(len(result['deferredGeneratorEvidence']['cases']), 2)
        rows[-1]['expectation']['output'] = 'changed'
        with self.assertRaises(ValueError): evaluate(rows, policy)
        rows = deepcopy(original); rows[-1]['selected'] = True
        with self.assertRaises(ValueError): evaluate(rows, policy)

    def test_standard_drop_projection_fails_closed(self):
        evidence = json.loads(DROP_EVIDENCE.read_text())
        generators = {x['caseID']: x for x in json.loads(GENERATOR_EVIDENCE.read_text())['cases']}
        rows = []
        for previous in evidence['cases']:
            row = deepcopy(previous)
            row.update(selected=True, admission='guarded_standard_drop', comparison='matched',
                       qualificationComparison='matched', referenceComparison='matched',
                       referenceQualificationComparison='matched', upstreamVerdict={'passed': True},
                       referenceUpstreamVerdict={'passed': True})
            if row['caseID'] in generators:
                row['expectation']['output'] = generators[row['caseID']]['historicalSeededOutput']
                row['expectationMaterialization'] = 'historical-seeded-closed-materialization'
            rows.append(row)
        original = deepcopy(rows)
        projected, info = project_standard_drop_admissions(rows)
        self.assertEqual(len(info['cases']), 56)
        self.assertEqual(rows, original)
        self.assertTrue(all(not row['selected'] for row in projected))
        for key, value in [('sourceDigest', 'changed'), ('parserMode', 'changed'),
                           ('referenceQualificationComparison', 'operational-error'), ('selected', False)]:
            changed = deepcopy(rows); changed[0][key] = value
            with self.assertRaises(ValueError): project_standard_drop_admissions(changed)
        changed = deepcopy(rows); changed.pop()
        with self.assertRaises(ValueError): project_standard_drop_admissions(changed)
        changed = deepcopy(rows)
        generated = next(row for row in changed if row['caseID'] in generators)
        generated['expectation']['output'] = 'wrong'
        with self.assertRaises(ValueError): project_standard_drop_admissions(changed)

    def test_generator_preparation_requires_exact_selected_cases(self):
        cases = json.loads(GENERATOR_EVIDENCE.read_text())['cases']
        rows = [{'caseID': item['caseID'], 'selected': True, 'admission': 'guarded_standard_drop',
                 'expectationMaterialization': 'historical-seeded-closed-materialization'} for item in cases]
        runs = {'fixturePreparation': 'inert-selection-v2; guarded standard Drop materialization; fixture expressions remain unevaluated'}
        check_generator_preparation(runs, rows)
        with self.assertRaises(ValueError): check_generator_preparation({'fixturePreparation': 'old'}, rows)
        changed = deepcopy(rows); changed[0]['caseID'] = 'changed'
        with self.assertRaises(ValueError): check_generator_preparation(runs, changed)
        changed = deepcopy(rows); changed[0]['selected'] = False
        with self.assertRaises(ValueError): check_generator_preparation(runs, changed)


if __name__ == '__main__':
    unittest.main()
