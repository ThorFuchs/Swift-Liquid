#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Regression cases for admission of release measurements, without timing code."""
import copy
import unittest
from compare_benchmarks import index_records, comparisons
from prepare_release import validate_dependency_benchmarks


def common_result():
    records = []
    for name in ['interpolation', 'filter-chain', 'loop', 'partial', 'date', 'custom-filter']:
        for mode in ['parse-and-render', 'reused-template', 'parse-and-render-metrics', 'reused-template-metrics']:
            records.append(record(name, mode))
    records += [record('inspection', 'parse-and-inspect'), record('inspection', 'inspect-reused-template')]
    return {'configuration': 'release', 'renderMode': 'all', 'workloads': records}


def record(name, mode):
    return {'name': name, 'mode': mode, 'samples': 25, 'warmupSamples': 10, 'repetitionsPerSample': 100,
            'sampleNanoseconds': list(range(1, 26)), 'medianNanoseconds': 13, 'p95Nanoseconds': 24,
            'minimumNanoseconds': 1, 'maximumNanoseconds': 25, 'outputBytes': 13, 'fnv1aChecksum': name}


def graph_result():
    records = []
    for name, nodes, edges, cycle, checksum in [('shared-diamond', 66, 128, 0, '454aa4f819527175'),
                                              ('cycle', 129, 129, 128, '33d9c72009eceaa5')]:
        for mode in ['source', 'parsed']:
            records.append({'workload': name, 'mode': mode, 'nodes': nodes, 'edges': edges, 'cycleMembers': cycle,
                            'checksumFNV1a64': checksum, 'samples': 25, 'warmupSamples': 10, 'repetitions': 20,
                            'nanosecondsPerOperation': list(range(1, 26)), 'medianNanoseconds': 13, 'p95Nanoseconds': 24})
    return {'schemaVersion': 1, 'operation': 'dependency-inspection', 'records': records}


class ReleaseEvidenceTests(unittest.TestCase):
    def test_all_ordinary_measured_and_inspection_modes_are_required(self):
        self.assertEqual(len(index_records(common_result())), 26)
        reduced = common_result()
        reduced['workloads'] = [r for r in reduced['workloads'] if not r['mode'].endswith('-metrics')]
        with self.assertRaises(RuntimeError):
            index_records(reduced)  # The former 14-record admission must no longer pass.
        duplicated = common_result()
        duplicated['workloads'][-1] = copy.deepcopy(duplicated['workloads'][0])
        with self.assertRaises(RuntimeError):
            index_records(duplicated)

    def test_common_samples_and_summaries_are_bound(self):
        for field, invalid in [('sampleNanoseconds', []), ('sampleNanoseconds', [float('nan')] * 25),
                               ('medianNanoseconds', 12), ('p95Nanoseconds', 23), ('repetitionsPerSample', 1)]:
            changed = common_result(); changed['workloads'][0][field] = invalid
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                index_records(changed)
        changed = common_result(); changed['renderMode'] = 'ordinary'
        with self.assertRaises(RuntimeError):
            index_records(changed)

    def test_metrics_modes_preserve_error_policy_identity(self):
        for mode in ['ordinary', 'metrics']:
            source = common_result()['workloads'][:]
            source = [r for r in source if r['name'] != 'inspection' and r['mode'].endswith('-metrics') == (mode == 'metrics')]
            source += [dict(r, mode='diagnostic-' + r['mode']) for r in source]
            indexed = index_records({'configuration': 'release', 'renderMode': mode, 'workloads': source}, mode)
            self.assertEqual(len(indexed), 24)
            self.assertIn(('interpolation', 'diagnostic-reused-template'), indexed)

    def test_cross_version_output_mismatches_are_failures(self):
        first = index_records(common_result())
        runs = [{'name': 'baseline', 'version': 'baseline'}, {'name': 'candidate', 'version': 'candidate'}]
        self.assertEqual(len(comparisons(runs, {'baseline': first, 'candidate': first}, ['baseline', 'candidate'])), 26)
        for field, value in [('fnv1aChecksum', 'different'), ('outputBytes', 99), ('samples', 24)]:
            second = copy.deepcopy(first); second[('interpolation', 'reused-template')][field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                comparisons(runs, {'baseline': first, 'candidate': second}, ['baseline', 'candidate'])

    def test_graph_shapes_checksums_modes_and_samples_are_bound(self):
        validate_dependency_benchmarks(graph_result())
        for field, value in [('nodes', 65), ('checksumFNV1a64', 'different'), ('samples', 24),
                             ('nanosecondsPerOperation', []), ('medianNanoseconds', 12), ('p95Nanoseconds', 23)]:
            changed = graph_result(); changed['records'][0][field] = value
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                validate_dependency_benchmarks(changed)
        changed = graph_result(); changed['records'].pop()
        with self.assertRaises(RuntimeError):
            validate_dependency_benchmarks(changed)


if __name__ == '__main__':
    unittest.main()
