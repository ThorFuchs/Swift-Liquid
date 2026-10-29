#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Local console controls; synthetic observations are not corpus results."""
import hashlib
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('console', ROOT / 'Tools/ConformanceConsole/server.py')
console = importlib.util.module_from_spec(spec)
spec.loader.exec_module(console)
CONFIG = {'specPath': '', 'referencePath': '', 'rubyPath': sys.executable, 'gemPath': ''}
IDENT = '20260101T000000000000Z-1234abcd'
SOURCE = {'commit': '1' * 40, 'tree': '2' * 40, 'clean': True}
SOURCES = [{'path': 'synthetic-control.txt', 'sha256': '3' * 64}]


class ConsoleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='liquid-console-control-')
        self.addCleanup(self.temp.cleanup)
        self.manager = console.Console(Path(self.temp.name), CONFIG)
        self.addCleanup(self.manager.close)

    def row(self, verdict='mismatched', selected=True, ident='control'):
        return {'caseID': ident, 'selected': selected, 'qualificationComparison': verdict,
                'comparison': 'matched', 'reason': 'synthetic control only'}

    def evidence(self, row=None):
        path = self.manager.state / IDENT
        path.mkdir()
        folder = path / 'artifacts/liquid-spec/independent/spec'
        folder.mkdir(parents=True)
        console.write_json(folder / 'ELIGIBILITY_MATRIX.json', [row or self.row()])
        console.write_json(folder / 'SPEC_RUNS.json', {'observedRows': 1, 'suites': [{'expandedVariants': 1}]})
        console.write_json(folder / 'PHASE_AND_DIAGNOSTIC_LEDGER.json', {'control': True})
        (folder / 'RPC_TRACES.jsonl').write_text('{}\n')
        hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir()}
        receipt = {'status': 'failed', 'sourceQualified': True, 'sourceUnchanged': True,
                   'sourceRevision': SOURCE, 'endingSourceRevision': SOURCE, 'sources': SOURCES,
                   'pins': {'spec': console.PINS['specPath'], 'ruby': console.PINS['referencePath']},
                   'runnerExitCode': 1, 'reportSHA256': hashes,
                   'commands': [{'log': 'diagnostic-ledger.log', 'exitCode': 0},
                                {'log': 'liquid-spec-runner.log', 'exitCode': 1}]}
        console.write_json(folder.parent / 'receipt.json', receipt)
        console.write_json(folder.parent.parent / 'receipt.json', receipt)
        return path, folder

    def execute(self, path, code=1):
        record = {'id': IDENT, 'status': 'running', 'source': SOURCE, 'sources': SOURCES,
                  'config': CONFIG, 'command': [sys.executable, '-c', 'raise SystemExit(' + str(code) + ')']}
        console.write_json(path / 'run.json', record)
        self.manager.active = IDENT
        self.manager.current_record = record
        self.manager._run(path, record)
        return console.read_json(path / 'run.json')

    def test_raw_match_cannot_override_qualified_failure(self):
        path, _ = self.evidence()
        result = self.execute(path)
        self.assertEqual(result['status'], 'failed')
        self.assertTrue(result['evidenceComplete'])
        self.assertEqual(result['counts']['mismatched'], 1)
        self.assertEqual(result['counts']['matched'], 0)

    def test_corrupt_digest_and_changed_source_are_runner_errors(self):
        path, folder = self.evidence()
        (folder / 'RPC_TRACES.jsonl').write_text('changed\n')
        self.assertEqual(self.execute(path)['status'], 'error')
        receipt = console.read_json(folder.parent / 'receipt.json')
        receipt['sourceRevision'] = dict(SOURCE, commit='4' * 40)
        console.write_json(folder.parent / 'receipt.json', receipt)
        self.assertEqual(self.execute(path)['status'], 'error')

    def test_incomplete_output_is_not_a_conformance_failure_or_pass(self):
        path = self.manager.state / IDENT
        path.mkdir()
        self.assertEqual(self.execute(path)['status'], 'error')

    def test_passing_receipt_cannot_hide_nonmatching_rows(self):
        path, folder = self.evidence()
        for file in [folder.parent / 'receipt.json', folder.parent.parent / 'receipt.json']:
            receipt = console.read_json(file)
            receipt['status'] = 'passed'
            console.write_json(file, receipt)
        self.assertEqual(self.execute(path, code=0)['status'], 'error')

    def test_exclusions_operational_and_duplicate_cases_stay_distinct(self):
        rows = [self.row('matched', ident='a'), self.row('operational-error', ident='b'),
                self.row('not-executed', False, ident='c')]
        self.assertEqual(console.summarize(rows), {'matched': 1, 'mismatched': 0, 'operational': 1, 'excluded': 1})
        with self.assertRaises(ValueError):
            console.summarize(rows + [rows[0]])
        with self.assertRaises(ValueError):
            console.summarize([self.row('future')])

    def test_run_directory_lock_and_path_boundaries(self):
        with self.assertRaises(ValueError):
            console.Console(self.manager.state, CONFIG)
        with self.assertRaises(ValueError):
            self.manager.directory('../outside')
        with self.assertRaises(ValueError):
            console.Console(ROOT / 'Artifacts/console-not-created', CONFIG)
        with self.assertRaises(ValueError):
            self.manager.save_config(dict(CONFIG, command='arbitrary'))

    def test_cancellation_drains_owned_process_and_retains_evidence(self):
        path = self.manager.state / IDENT
        path.mkdir()
        record = {'id': IDENT, 'status': 'running', 'source': SOURCE, 'sources': SOURCES,
                  'config': CONFIG, 'command': [sys.executable, '-c', 'import time; time.sleep(30)']}
        console.write_json(path / 'run.json', record)
        self.manager.active = IDENT
        self.manager.current_record = record
        self.manager.worker = threading.Thread(target=self.manager._run, args=(path, record))
        self.manager.worker.start()
        deadline = time.monotonic() + 5
        while self.manager.process is None and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertIsNotNone(self.manager.process)
        with self.assertRaises(ValueError):
            self.manager.cancel('another-owner')
        self.manager.cancel(IDENT)
        self.manager.worker.join(timeout=10)
        self.assertFalse(self.manager.worker.is_alive())
        self.assertEqual(console.read_json(path / 'run.json')['status'], 'cancelled')
        self.assertTrue((path / 'console.log').is_file())

    def test_restart_does_not_claim_an_old_running_process_is_live(self):
        path = self.manager.state / IDENT
        path.mkdir()
        console.write_json(path / 'run.json', {'id': IDENT, 'status': 'running'})
        self.assertEqual(self.manager.record(IDENT)['status'], 'interrupted')
        self.assertEqual(console.read_json(path / 'run.json')['status'], 'running')

    def test_http_auth_origin_mime_and_file_confinement(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), console.handler(self.manager, 'control-token'))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        client = HTTPConnection('127.0.0.1', server.server_port, timeout=5)
        self.addCleanup(client.close)
        def request(method, path, body=None, headers=None):
            client.request(method, path, body, headers or {})
            response = client.getresponse()
            response.read()
            return response
        self.assertEqual(request('GET', '/api/state').status, 401)
        launch = request('GET', '/?token=control-token')
        self.assertEqual(launch.status, 303)
        self.assertIn('HttpOnly; SameSite=Strict', launch.getheader('Set-Cookie'))
        auth = {'Cookie': 'liquid_console_' + str(server.server_port) + '=control-token'}
        self.assertEqual(request('GET', '/api/state', headers=auth).status, 200)
        self.assertEqual(request('GET', '/.git/config', headers=auth).status, 404)
        self.assertEqual(request('GET', '/api/state', headers=dict(auth, Host='attacker.example')).status, 403)
        self.assertEqual(request('POST', '/api/run', '{}', dict(auth, Origin='http://attacker.example', **{'Content-Type': 'application/json'})).status, 403)
        self.assertEqual(request('POST', '/api/config', '{}', dict(auth, **{'Content-Type': 'text/plain'})).status, 415)
        self.assertEqual(request('POST', '/api/config', '[]', dict(auth, **{'Content-Type': 'application/json'})).status, 400)
        page = request('GET', '/', headers=auth)
        self.assertEqual(page.status, 200)
        self.assertIn("frame-ancestors 'none'", page.getheader('Content-Security-Policy'))

    def test_external_output_option_cannot_redirect_unadapted_lanes(self):
        for lane, path in [('docs', self.temp.name), ('liquid-spec', str(ROOT / 'Artifacts/should-not-exist'))]:
            result = subprocess.run([sys.executable, '-B', str(ROOT / 'Scripts/ci.py'), '--lane', lane,
                                     '--output-root', path], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('--output-root', result.stderr)


if __name__ == '__main__':
    unittest.main()
