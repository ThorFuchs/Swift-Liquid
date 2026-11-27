#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Adversarial checks for inventory identity reconciliation."""
import copy
import unittest
from compare_sl21_inventory import compare
from compare_sl21_materialization import compare as compare_materialization


class IdentityComparisonTests(unittest.TestCase):
    def setUp(self):
        self.pin = 'test-pin'
        self.rows = [{'caseID': str(i), 'sourceLocation': {'file': 'fixture.yml', 'line': i + 1},
                      'sourceDigest': 'd' * 64, 'parserMode': 'strict2', 'renderMode': 'raise',
                      'featureTags': ['strict2_parsing']} for i in range(5112)]
        for index, row in enumerate(self.rows):
            row['selection'] = {'selected': index >= 425, 'reason': 'held' if index < 425 else None,
                                'admission': 'unused_filesystem_callback' if 425 <= index < 488 else None}
        self.inventory = {'specPin': self.pin, 'variants': copy.deepcopy(self.rows)}
        self.earlier = [dict(row, selected=(index >= 488), reason='held' if index < 425 else 'other') for index, row in enumerate(self.rows)]
        self.holds = {'baseline': {'specCommit': self.pin}, 'cases': copy.deepcopy(self.rows[:425])}
        self.admissions = {'specPin': self.pin, 'filesystemCandidates': copy.deepcopy(self.rows[425:488]),
                           'rangeMetadataCandidates': [], 'commentCandidates': [],
                           'longStringCandidates': [], 'missingFileCandidates': []}

    def test_comparison_accepts_consistent_identity_and_partition(self):
        self.assertEqual(len(compare(self.inventory, self.earlier, self.holds, self.admissions)), 5112)

    def test_duplicate_and_missing_identities_fail_closed(self):
        self.inventory['variants'][1] = self.inventory['variants'][0]
        with self.assertRaises(ValueError):
            compare(self.inventory, self.earlier, self.holds, self.admissions)
        self.inventory['variants'] = copy.deepcopy(self.rows)
        self.inventory['variants'].pop()
        with self.assertRaises(ValueError):
            compare(self.inventory, self.earlier, self.holds, self.admissions)

    def test_changed_identity_or_policy_fails_closed(self):
        self.inventory['variants'][500]['sourceDigest'] = 'changed'
        with self.assertRaises(ValueError):
            compare(self.inventory, self.earlier, self.holds, self.admissions)
        self.inventory['variants'][500]['sourceDigest'] = 'd' * 64
        self.admissions['filesystemCandidates'][0]['sourceDigest'] = 'changed'
        with self.assertRaises(ValueError):
            compare(self.inventory, self.earlier, self.holds, self.admissions)

    def test_materialization_rejects_changed_and_excluded_inputs(self):
        digest = {'sha256': 'digest', 'jsonBytes': 1}
        expectation = {'output': '', 'outputPattern': None, 'errors': {}}
        traces = {}
        for index, item in enumerate(self.inventory['variants']):
            self.earlier[index]['expectation'] = expectation
            item['materialized'] = ({'template': digest, 'environment': digest, 'filesystem': digest,
                                     'expectation': expectation} if item['selection']['selected'] else None)
            if self.earlier[index]['selected']:
                traces[item['caseID']] = {'compile': {'template': digest, 'filesystem': digest},
                                         'render': {'environment': digest}}
        self.assertEqual(len(compare_materialization(self.inventory, self.earlier, traces)), 5112)
        self.inventory['variants'][0]['materialized'] = {'unexpected': 'materialized'}
        with self.assertRaises(ValueError):
            compare_materialization(self.inventory, self.earlier, traces)
        self.inventory['variants'][0]['materialized'] = None
        traces['500']['render']['environment'] = {'sha256': 'changed', 'jsonBytes': 1}
        with self.assertRaises(ValueError):
            compare_materialization(self.inventory, self.earlier, traces)


if __name__ == '__main__':
    unittest.main()
