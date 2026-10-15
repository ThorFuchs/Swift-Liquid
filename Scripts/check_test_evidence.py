#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Exercise evidence admission against damaged streams and the actual Swift runner."""
import copy
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from ci import ROOT, environment, swift
from test_evidence import analyze, qualify


def event(kind, **payload):
    return {'version': 0, 'kind': 'event', 'payload': {'kind': kind, **payload}}


TEST = 'Probe.examples(_:)/Probe.swift:1:1'
EXPECTED = {'Probe.examples(_:)': 2}


def complete():
    return [{'version': 0, 'kind': 'test', 'payload': {'kind': 'function', 'id': TEST,
        'isParameterized': True, '_testCases': [{'id': 'a'}, {'id': 'b'}]}},
        event('runStarted'), event('testStarted', testID=TEST),
        event('testCaseStarted', testID=TEST, _testCase={'id': 'a'}),
        event('testCaseEnded', testID=TEST, _testCase={'id': 'a'}),
        event('testCaseStarted', testID=TEST, _testCase={'id': 'b'}),
        event('testCaseEnded', testID=TEST, _testCase={'id': 'b'}),
        event('testEnded', testID=TEST), event('runEnded')]


class TestEvidenceTests(unittest.TestCase):
    def check(self, rows, expected=EXPECTED, exit_code=0, terminated=True):
        with tempfile.TemporaryDirectory(prefix='liquid-events-') as directory:
            path = Path(directory) / 'events.jsonl'
            path.write_text('\n'.join(json.dumps(row) for row in rows) + ('\n' if terminated else ''))
            return analyze(path, expected, exit_code)

    def test_parallel_cases_can_interleave(self):
        rows = complete(); rows[4], rows[5] = rows[5], rows[4]
        report = self.check(rows)
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['completedCases'], 2)

    def test_exit_status_cannot_be_hidden_by_a_complete_stream(self):
        self.assertEqual(self.check(complete(), exit_code=1)['status'], 'failed')

    def test_missing_or_filtered_function_is_not_a_pass(self):
        self.assertEqual(self.check([event('runStarted'), event('runEnded')])['status'], 'failed')
        self.assertEqual(self.check(complete(), {**EXPECTED, 'Probe.missing()': None})['status'], 'failed')

    def test_missing_duplicate_and_unfinished_cases_are_rejected(self):
        for index in [3, 4, 5, 6, 7, 8]:
            rows = complete(); rows.pop(index)
            with self.subTest(missing=index):
                self.assertEqual(self.check(rows)['status'], 'failed')
        rows = complete(); rows.insert(4, copy.deepcopy(rows[3]))
        self.assertEqual(self.check(rows)['status'], 'failed')
        rows = complete(); rows[0]['payload']['_testCases'].pop(); rows[5:7] = []
        self.assertEqual(self.check(rows)['status'], 'failed')

    def test_skips_known_issues_and_cancellations_are_explicit(self):
        for kind, payload in [('testSkipped', {'testID': TEST}),
                              ('issueRecorded', {'issue': {'isKnown': False}}),
                              ('issueRecorded', {'issue': {'isKnown': True}}),
                              ('testCancelled', {'testID': TEST}),
                              ('testCaseCancelled', {'testID': TEST})]:
            rows = complete(); rows.insert(-1, event(kind, **payload))
            with self.subTest(kind=kind, payload=payload):
                self.assertEqual(self.check(rows)['status'], 'failed')

    def test_truncated_unknown_and_reversed_streams_fail_closed(self):
        self.assertEqual(self.check(complete(), terminated=False)['status'], 'failed')
        for mutation in ['version', 'kind', 'adapter', 'reversed', 'empty', 'duplicate', 'malformed']:
            rows = complete()
            if mutation == 'version': rows[0]['version'] = 1
            elif mutation == 'kind': rows.insert(-1, event('newKind'))
            elif mutation == 'adapter': del rows[3]['payload']['_testCase']
            elif mutation == 'reversed': rows[1], rows[-1] = rows[-1], rows[1]
            elif mutation == 'empty': rows[0]['payload']['_testCases'] = []
            elif mutation == 'duplicate': rows.insert(1, copy.deepcopy(rows[0]))
            else: rows[0]['payload'] = None
            with self.subTest(mutation=mutation):
                self.assertEqual(self.check(rows)['status'], 'failed')

    def test_malformed_json_and_inventory_fail_with_a_report(self):
        with tempfile.TemporaryDirectory(prefix='liquid-invalid-evidence-') as directory:
            path = Path(directory) / 'events.jsonl'
            for raw in ['[]\n', 'null\n', '{"version":0,"version":0}\n', '{"x":NaN}\n', '{invalid}\n']:
                path.write_text(raw)
                with self.subTest(raw=raw):
                    self.assertEqual(analyze(path, EXPECTED)['status'], 'failed')
            path.write_text('\n'.join(json.dumps(row) for row in complete()) + '\n')
            inventory = Path(directory) / 'inventory.json'
            for contents in [{}, [], {'schemaVersion': 1, 'functions': {}},
                             {'schemaVersion': 1, 'functions': {'Probe.examples(_:)': 0}},
                             {'schemaVersion': 1, 'functions': EXPECTED, 'threadFunctions': ['absent']}]:
                inventory.write_text(json.dumps(contents))
                with self.subTest(contents=contents):
                    self.assertEqual(qualify(path, inventory, 'thread')['status'], 'failed')

    def test_actual_runner_pass_failure_disabled_known_empty_and_filter(self):
        output = Path(os.environ.get('LIQUID_TEST_EVIDENCE_PROBE_OUTPUT', ROOT / 'Artifacts/test-evidence-probe'))
        output.mkdir(parents=True, exist_ok=True)
        receipts = []
        for index, (name, expected, admits) in enumerate([
            ('passing', {'RunnerProbeTests.passing(_:)': 2}, True),
            ('disabled', {'RunnerProbeTests.disabled()': None}, False),
            ('failing', {'RunnerProbeTests.failing()': None}, False),
            ('known', {'RunnerProbeTests.known()': None}, False),
            ('empty', {'RunnerProbeTests.empty(_:)': 1}, False),
            ('absent', {'RunnerProbeTests.absent()': None}, False),
            ('caseFailure', {'RunnerProbeTests.caseFailure(_:)': 2}, False),
        ]):
            path = output / (name + '.events.jsonl')
            path.unlink(missing_ok=True)
            command = swift() + ['test', '--package-path', str(ROOT / 'Tools/TestEvidenceProbe'),
                '--filter', name, '--event-stream-version', '0', '--event-stream-output-path', str(path)]
            if index: command.append('--skip-build')
            command += shlex.split(environment().get('LIQUID_SWIFTPM_FLAGS', ''))
            result = subprocess.run(command, cwd=ROOT, env=environment(), capture_output=True, text=True)
            (output / (name + '.log')).write_text(result.stdout + result.stderr)
            report = analyze(path, expected, result.returncode)
            receipts.append({'name': name, 'command': command, **report})
            with self.subTest(name=name):
                self.assertEqual(report['status'] == 'passed', admits, report)
                # Reject for observed runner behavior, not an accidental build/configuration failure.
                self.assertIn('eventsSHA256', report)
                if name in ['disabled', 'empty']: self.assertEqual(report['skipped'], 1)
                if name == 'known':
                    self.assertEqual(report['knownIssues'], 1)
                    self.assertEqual(report['recordedIssues'][0]['testID'].split('/')[0], 'RunnerProbeTests.known()')
                if name == 'failing': self.assertGreater(report['issues'], 0)
                if name == 'caseFailure':
                    self.assertEqual(report['issues'], 1)
                    self.assertIsNotNone(report['recordedIssues'][0]['caseID'])
                    self.assertEqual(report['completedCases'], 2)
        (output / 'receipt.json').write_text(json.dumps(receipts, indent=2) + '\n')


if __name__ == '__main__':
    unittest.main()
