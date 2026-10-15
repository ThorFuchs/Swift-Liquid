#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Regression cases for admission of release measurements, without timing code."""
import copy
import unittest
from compare_benchmarks import index_records, comparisons, distribution
from prepare_release import validate_dependency_benchmarks
from maintenance_evidence import validate as validate_maintenance, SOURCES, OUTPUTS, UNITS, PARTIAL, POLICIES, checksum


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

    def test_observed_variance_cannot_hide_behind_equal_medians(self):
        self.assertEqual(distribution([9, 10, 10, 10, 10, 11])['medianAbsoluteDeviationNanoseconds'], 0)
        self.assertEqual(distribution([9, 10, 10, 10, 10, 11])['rangePercent'], 20)
        for values in [[], [0], [float('nan')], [float('inf')], [-1]]:
            with self.subTest(values=values), self.assertRaises(RuntimeError): distribution(values)
        first = index_records(common_result()); second = copy.deepcopy(first)
        second[('interpolation', 'reused-template')]['medianNanoseconds'] = 26
        runs = [{'name': str(i), 'version': 'baseline' if i % 2 == 0 else 'candidate'} for i in range(12)]
        indexed = {r['name']: first for r in runs}; indexed['0'] = second
        rows = comparisons(runs, indexed, ['baseline', 'candidate'])
        row = next(r for r in rows if r['name'] == 'interpolation' and r['mode'] == 'reused-template')
        self.assertFalse(row['requiresReview'])
        self.assertTrue(row['varianceRequiresReview'])
        self.assertEqual(row['runMedianDistributions']['baseline']['observations'], 6)

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


def maintenance_result():
    def timings():
        return {'samples': 25, 'warmupSamples': 5, 'medianNanoseconds': 13,
                'p95Nanoseconds': 24, 'minimumNanoseconds': 1, 'maximumNanoseconds': 25}
    large = [dict(timings(), workload=name, mode=mode, repetitions=1, units=UNITS[name],
                  sourceBytes=len(SOURCES[name].encode()) + (len(PARTIAL.encode()) if name == 'partial-fanout' else 0),
                  outputBytes=len(output.encode()), checksumFNV1a64=checksum(output), nanosecondsPerOperation=list(range(1, 26)))
             for name, output in OUTPUTS.items() for mode in ['source', 'parsed']]
    cancellation = [dict(timings(), policy=policy, mode=mode, host=host, cancelledSamples=25,
                         continuedSamples=0, healthyReuse=True, cancelToCompletionNanoseconds=list(range(1, 26)),
                         cancelToReleaseNanoseconds=[0.5] * 25 if host == 'explicit-release' else [],
                         releaseToCompletionNanoseconds=[i - 0.5 for i in range(1, 26)] if host == 'explicit-release' else [])
                    for policy in POLICIES for mode in ['source', 'parsed'] for host in ['cooperative', 'explicit-release']]
    return {'schemaVersion': 1, 'configuration': 'release', 'operation': 'measured-maintenance',
            'schedulerConfiguration': 'concurrent driver, detached workers, Dispatch cancellation controller',
            'largeWorkloads': large, 'cancellation': cancellation,
            'runnableCancellation': [dict(workload='runnable-escape', policy=policy, mode=mode, samples=25,
                warmupSamples=5, inputBytes=UNITS['large-escape'], expectedOutputBytes=len(OUTPUTS['large-escape'].encode()),
                checksumFNV1a64=checksum(OUTPUTS['large-escape']), healthyReuse=True,
                observations=[{'outcome': 'cancelled', 'completionRelativeToRequestNanoseconds': i} for i in range(1, 26)],
                cancelledSamples=25, completedSamples=0, cancelledMedianNanoseconds=13, cancelledP95Nanoseconds=24)
                for policy in POLICIES for mode in ['source', 'parsed']]}


class MaintenanceEvidenceTests(unittest.TestCase):
    def test_complete_observations_have_no_latency_deadline(self):
        result = validate_maintenance(maintenance_result())
        self.assertEqual((result['largeRecords'], result['cancellationRecords']), (6, 16))
        self.assertIsNone(result['latencyDeadline'])
        slower = maintenance_result()
        for record in slower['largeWorkloads']:
            for field in ['medianNanoseconds', 'p95Nanoseconds', 'minimumNanoseconds', 'maximumNanoseconds']:
                record[field] *= 1_000_000
            record['nanosecondsPerOperation'] = [value * 1_000_000 for value in record['nanosecondsPerOperation']]
        validate_maintenance(slower)  # Admission is completeness/correctness, not a speed contest.

    def test_racing_completions_are_not_cancellation_successes(self):
        result = maintenance_result(); record = result['runnableCancellation'][0]
        record.update(observations=[{'outcome': 'completed-before-request', 'completionRelativeToRequestNanoseconds': -1}] * 25,
                      cancelledSamples=0, completedSamples=25, cancelledMedianNanoseconds=None, cancelledP95Nanoseconds=None)
        validate_maintenance(result)
        record['cancelledSamples'] = 25
        with self.assertRaises(RuntimeError): validate_maintenance(result)
        result = maintenance_result(); result['runnableCancellation'][0]['observations'][0]['completionRelativeToRequestNanoseconds'] = -1
        with self.assertRaises(RuntimeError): validate_maintenance(result)

    def test_missing_duplicate_or_corrupted_large_workloads_fail(self):
        for change in ['missing', 'duplicate', 'checksum', 'units', 'raw', 'summary']:
            result = maintenance_result(); records = result['largeWorkloads']
            if change == 'missing': records.pop()
            elif change == 'duplicate': records[-1] = copy.deepcopy(records[0])
            elif change == 'checksum': records[0]['checksumFNV1a64'] = 'different'
            elif change == 'units': records[0]['units'] += 1
            elif change == 'raw': records[0]['nanosecondsPerOperation'][0] = float('nan')
            else: records[0]['p95Nanoseconds'] = 25
            with self.subTest(change=change), self.assertRaises(RuntimeError): validate_maintenance(result)

    def test_cancellation_accounting_and_shared_clock_boundaries_are_required(self):
        for change in ['missing', 'duplicate', 'completed', 'continued', 'reuse', 'host', 'interval', 'zero']:
            result = maintenance_result(); records = result['cancellation']
            if change == 'missing': records.pop()
            elif change == 'duplicate': records[-1] = copy.deepcopy(records[0])
            elif change == 'completed': records[0]['cancelledSamples'] = 24
            elif change == 'continued': records[0]['continuedSamples'] = 1
            elif change == 'reuse': records[0]['healthyReuse'] = False
            elif change == 'host': records[0]['cancelToReleaseNanoseconds'] = [1] * 25
            elif change == 'interval': records[1]['releaseToCompletionNanoseconds'] = [100] * 25
            else: records[0]['cancelToCompletionNanoseconds'][0] = 0
            with self.subTest(change=change), self.assertRaises(RuntimeError): validate_maintenance(result)


if __name__ == '__main__':
    unittest.main()
