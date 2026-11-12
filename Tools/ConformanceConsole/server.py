#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Local, dependency-free UI for the existing source-bound liquid-spec lane."""
import argparse
import collections
import datetime
import fcntl
import hashlib
import hmac
import http.cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import signal
import subprocess
import sys
import threading
import time
from urllib.parse import parse_qs, urlsplit
import uuid

ROOT = Path(__file__).resolve().parents[2]
ASSETS = Path(__file__).resolve().parent / 'web'
PINS = {'specPath': '84bf25e0edbca5f7e530574788b0f875ab331f50',
        'referencePath': '4e39ae4cc3da73921923c0669e0fc84a66b2f696'}
CONFIG_KEYS = {'specPath', 'referencePath', 'rubyPath', 'gemPath'}
RUN_ID = re.compile(r'^[0-9]{8}T[0-9]{12}Z-[0-9a-f]{8}$')


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def read_json(path):
    if path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError('Evidence file exceeds the console read bound')
    return json.loads(path.read_bytes())


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    with temporary.open('w') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    temporary.chmod(0o600)
    os.replace(temporary, path)


def child_environment(config):
    ruby = str(Path(config['rubyPath']).expanduser())
    env = {key: os.environ[key] for key in ['HOME', 'USER', 'LOGNAME', 'TMPDIR'] if key in os.environ}
    env.update(PATH=str(Path(ruby).parent) + ':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
               TZ='UTC', PYTHONDONTWRITEBYTECODE='1', LIQUID_RUBY=ruby,
               GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1', GIT_NO_REPLACE_OBJECTS='1',
               GIT_TERMINAL_PROMPT='0', LIQUID_SWIFTPM_FLAGS='--jobs 2',
               GIT_CONFIG_COUNT='3', GIT_CONFIG_KEY_0='core.hooksPath', GIT_CONFIG_VALUE_0='/dev/null',
               GIT_CONFIG_KEY_1='gc.auto', GIT_CONFIG_VALUE_1='0',
               GIT_CONFIG_KEY_2='maintenance.auto', GIT_CONFIG_VALUE_2='false')
    if config.get('gemPath'):
        env['GEM_PATH'] = config['gemPath']
    return env


def observe(command, env, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=30)
    return {'command': command, 'exit': result.returncode,
            'stdout': result.stdout[-16000:], 'stderr': result.stderr[-16000:]}


def git(*args):
    return ['git', '--no-optional-locks', '-c', 'core.fsmonitor=false',
            '-c', 'core.hooksPath=/dev/null', *args]


def preflight(config):
    env = child_environment(config)
    checks = []
    source = {}
    def check(name, command, accepts, cwd=ROOT):
        try:
            result = observe(command, env, cwd)
            result.update(name=name, passed=result['exit'] == 0 and accepts(result['stdout']))
        except (OSError, subprocess.TimeoutExpired, ValueError) as error:
            result = {'name': name, 'passed': False, 'error': str(error)}
        checks.append(result)
        return result
    h = check('Source commit', git('rev-parse', 'HEAD'), lambda x: bool(re.fullmatch('[0-9a-f]{40}\n?', x)))
    t = check('Source tree', git('rev-parse', 'HEAD^{tree}'), lambda x: bool(re.fullmatch('[0-9a-f]{40}\n?', x)))
    clean = check('Clean checkout', git('status', '--porcelain', '--untracked-files=all'), lambda x: not x.strip())
    source.update(commit=h.get('stdout', '').strip(), tree=t.get('stdout', '').strip(), clean=clean['passed'])
    check('Swift 6.4+', ['xcrun', 'swift', '--version'],
          lambda x: bool(re.search(r'Swift version (?:6\.[4-9]|6\.[1-9][0-9]|[7-9]\.)', x)))
    check('Ruby 4.0.1', [config['rubyPath'], '--version'], lambda x: x.startswith('ruby 4.0.1 '))
    for key, pin in PINS.items():
        path = Path(config.get(key, '')).expanduser()
        label = 'Pinned liquid-spec' if key == 'specPath' else 'Pinned Ruby Liquid'
        check(label, git('-C', str(path), 'rev-parse', 'HEAD'), lambda x, p=pin: x.strip() == p)
        check(label + ' clean', git('-C', str(path), 'status', '--porcelain'), lambda x: not x.strip())
    code = ('require "json"; wanted={"activesupport"=>"8.1.4","base64"=>"0.3.0",'
            '"super_diff"=>"0.19.0","date"=>"3.5.1","time"=>"0.4.2"}; '
            'rows=wanted.to_h { |n,v| [n,Gem::Specification.find_all_by_name(n,v).any?] }; '
            'puts JSON.generate(rows); exit(rows.values.all? ? 0 : 1)')
    check('Pinned development gems', [config['rubyPath'], '-e', code], lambda x: bool(x.strip()))
    return {'checkedUTC': now(), 'ready': all(c['passed'] for c in checks), 'source': source, 'checks': checks}


def summarize(rows):
    ids = [r['caseID'] for r in rows]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate case identities in evidence')
    counts = collections.Counter()
    for row in rows:
        if not isinstance(row.get('selected'), bool):
            raise ValueError('Missing case selection metadata')
        verdict = row.get('qualificationComparison')
        if not row['selected']:
            if verdict != 'not-executed' or not row.get('reason'):
                raise ValueError('Excluded row lacks explicit outcome/reason')
            counts['excluded'] += 1
        elif verdict in ['matched', 'mismatched']:
            counts[verdict] += 1
        elif verdict in ['operational-error', 'domain-divergence']:
            counts['operational'] += 1
        else:
            raise ValueError('Unrecognized qualified verdict')
    return {key: counts[key] for key in ['matched', 'mismatched', 'operational', 'excluded']}


def source_inventory(env):
    result = subprocess.run(git('ls-files', '-z'), cwd=ROOT, env=env, capture_output=True, check=True)
    if len(result.stdout) > 1024 * 1024:
        raise ValueError('Source inventory exceeds the console bound')
    rows = []
    for raw in result.stdout.split(b'\0'):
        if not raw:
            continue
        name = raw.decode('utf-8')
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Source inventory requires regular tracked files')
        rows.append({'path': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return rows


class Console:
    def __init__(self, state, config, timeout=1800):
        self.state = state.expanduser().resolve()
        if self.state.is_relative_to(ROOT):
            raise ValueError('Run storage must be outside the source checkout')
        self.state.mkdir(parents=True, mode=0o700, exist_ok=True)
        if self.state.stat().st_uid != os.getuid():
            raise ValueError('Run storage must be owned by the current user')
        self.state.chmod(0o700)
        self.lease = (self.state / 'console.lock').open('a')
        try:
            fcntl.flock(self.lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.lease.close()
            raise ValueError('Another console owns this run directory')
        self.config = {key: config.get(key, '') for key in CONFIG_KEYS}
        if (self.state / 'config.json').exists():
            saved = read_json(self.state / 'config.json')
            if set(saved) != CONFIG_KEYS or any(not isinstance(v, str) for v in saved.values()):
                raise ValueError('Invalid saved setup; preserve it and supply a fresh state directory')
            self.config.update(saved)
        self.lock = threading.RLock()
        self.process = None
        self.active = None
        self.current_record = None
        self.worker = None
        self.timeout = timeout

    def save_config(self, value):
        if set(value) != CONFIG_KEYS or any(not isinstance(v, str) or len(v) > 4096 for v in value.values()):
            raise ValueError('Expected only specPath, referencePath, rubyPath and gemPath strings')
        with self.lock:
            if self.active:
                raise ValueError('Wait for the current run before changing setup')
            self.config = value.copy()
            write_json(self.state / 'config.json', self.config)

    def directory(self, ident):
        if not RUN_ID.fullmatch(ident):
            raise ValueError('Invalid run identity')
        path = self.state / ident
        if path.is_symlink() or path.resolve().parent != self.state or not path.is_dir():
            raise ValueError('Unknown run')
        return path

    def rows(self, ident):
        path = self.directory(ident) / 'artifacts/liquid-spec/independent/spec/ELIGIBILITY_MATRIX.json'
        if not path.exists():
            return []
        return read_json(path)

    def record(self, ident):
        path = self.directory(ident)
        result = read_json(path / 'run.json')
        if result['status'] == 'running' and ident != self.active:
            result.update(status='interrupted', originalStatus='running')
        try:
            rows = self.rows(ident)
            result.update(counts=summarize(rows), rowsRecorded=len(rows))
        except (ValueError, OSError, KeyError):
            result.update(counts=None, rowsRecorded=None)
        result['phase'] = result['status']
        if result['status'] == 'running':
            inner = path / 'artifacts/liquid-spec/independent'
            result['phase'] = 'Running official cases' if (inner / 'spec').exists() else (
                'Checking protocol and bridge' if (inner / 'adapter-build.log').exists() else 'Building adapter and checking source')
        return result

    def list_runs(self):
        runs = []
        for path in sorted(self.state.iterdir(), reverse=True):
            if RUN_ID.fullmatch(path.name) and path.is_dir() and not path.is_symlink():
                try:
                    runs.append(self.record(path.name))
                except (ValueError, OSError, KeyError):
                    continue
        return runs

    def start(self):
        with self.lock:
            if self.active:
                raise ValueError('A suite is already running')
            ready = preflight(self.config)
            if not ready['ready']:
                raise ValueError('Setup checks must all pass before running')
            sources = source_inventory(child_environment(self.config))
            ident = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '-' + uuid.uuid4().hex[:8]
            path = self.state / ident
            path.mkdir(mode=0o700)
            command = [sys.executable, '-B', 'Scripts/ci.py', '--lane', 'liquid-spec',
                       '--spec-path', self.config['specPath'], '--reference-path', self.config['referencePath'],
                       '--output-root', str(path / 'artifacts')]
            record = {'id': ident, 'startedUTC': now(), 'status': 'running', 'source': ready['source'],
                      'sources': sources,
                      'command': command, 'config': self.config.copy(), 'preflight': ready,
                      'scope': 'Pinned functional suites only; not complete-language or release acceptance'}
            write_json(path / 'run.json', record)
            self.active = ident
            self.current_record = record
            self.worker = threading.Thread(target=self._run, args=(path, record), daemon=True)
            self.worker.start()
            return record

    def _run(self, path, record):
        try:
            with (path / 'console.log').open('wb') as log:
                with self.lock:
                    if record.get('cancelRequested'):
                        record.update(status='cancelled', endedUTC=now())
                        return
                    self.process = subprocess.Popen(record['command'], cwd=ROOT, env=child_environment(record['config']),
                                                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = self.process.wait(timeout=self.timeout)
                except subprocess.TimeoutExpired:
                    record['timedOut'] = True
                    self._terminate()
                    code = self.process.wait()
                record['exitCode'] = code
            outer = path / 'artifacts/liquid-spec/receipt.json'
            inner = path / 'artifacts/liquid-spec/independent/receipt.json'
            matrix = path / 'artifacts/liquid-spec/independent/spec/ELIGIBILITY_MATRIX.json'
            if record.get('cancelRequested') or record.get('timedOut'):
                record['status'] = 'timed_out' if record.get('timedOut') else 'cancelled'
            elif outer.exists() and inner.exists() and matrix.exists():
                receipt, evidence = read_json(outer), read_json(inner)
                summary = read_json(matrix.parent / 'SPEC_RUNS.json')
                rows = read_json(matrix)
                counts = summarize(rows)
                source = record['source']
                valid = all(x.get('sourceQualified') is True and x.get('sourceUnchanged') is True
                            and x.get('sourceRevision') == source and x.get('endingSourceRevision') == source
                            for x in [receipt, evidence])
                valid = valid and len(rows) == summary['observedRows'] == sum(s['expandedVariants'] for s in summary['suites'])
                valid = valid and receipt['sources'] == evidence['sources']
                def mapping(items):
                    mapped = {r['path']: r['sha256'] for r in items}
                    if not mapped or len(mapped) != len(items):
                        raise ValueError('Empty or ambiguous source inventory')
                    return mapped
                valid = valid and mapping(receipt['sources']) == mapping(record['sources'])
                valid = valid and all(c['exitCode'] == 0 for c in evidence['commands'] if c['log'] != 'liquid-spec-runner.log')
                valid = valid and any(c['log'] == 'diagnostic-ledger.log' and c['exitCode'] == 0 for c in evidence['commands'])
                valid = valid and evidence.get('pins') == {'spec': PINS['specPath'], 'ruby': PINS['referencePath']}
                valid = valid and set(evidence.get('reportSHA256', {})) == {
                    'PHASE_AND_DIAGNOSTIC_LEDGER.json', 'ELIGIBILITY_MATRIX.json', 'SPEC_RUNS.json', 'RPC_TRACES.jsonl'}
                for name, digest in evidence.get('reportSHA256', {}).items():
                    if Path(name).name != name or hashlib.sha256((matrix.parent / name).read_bytes()).hexdigest() != digest:
                        valid = False
                if not valid:
                    raise ValueError('Incomplete or differently sourced conformance receipts')
                selected_count = counts['matched'] + counts['mismatched'] + counts['operational']
                passed = (code == 0 and receipt['status'] == evidence['status'] == 'passed'
                          and selected_count > 0 and counts['mismatched'] == counts['operational'] == 0)
                expected_failure = (code == 1 and evidence.get('runnerExitCode') == 1
                                    and receipt['status'] == evidence['status'] == 'failed'
                                    and counts['mismatched'] + counts['operational'] > 0)
                if not passed and not expected_failure:
                    raise ValueError('Runner failed outside the recorded conformance verdict; inspect logs')
                record.update(status='passed' if passed else 'failed', counts=counts, rowsRecorded=len(rows),
                              matrixSHA256=hashlib.sha256(matrix.read_bytes()).hexdigest(), evidenceComplete=True)
            else:
                record.update(status='error', error='Runner ended without complete evidence; inspect retained log')
        except (OSError, ValueError, KeyError) as error:
            record.update(status='error', error=str(error))
        finally:
            record['endedUTC'] = now()
            with self.lock:
                write_json(path / 'run.json', record)
                self.active = None
                self.process = None
                self.current_record = None

    def _terminate(self):
        with self.lock:
            process = self.process
            if process is None or process.poll() is not None:
                return
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    def cancel(self, ident):
        with self.lock:
            if self.active != ident:
                raise ValueError('Only the currently owned run can be cancelled')
            if self.process is not None and self.process.poll() is not None:
                raise ValueError('The run is already finalizing its evidence')
            # The worker owns the same record; persist cancellation separately before signalling.
            path = self.directory(ident)
            record = self.current_record
            record['cancelRequested'] = True
            write_json(path / 'run.json', record)
        self._terminate()

    def close(self):
        if self.active:
            try:
                self.cancel(self.active)
            except ValueError:
                pass
        if self.worker:
            self.worker.join(timeout=10)
        self.lease.close()


def handler(console, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # Never log bootstrap credentials or fixture data to a shared terminal.

        def origin(self):
            return 'http://127.0.0.1:' + str(self.server.server_port)

        def headers_ok(self):
            return self.headers.get('Host') == '127.0.0.1:' + str(self.server.server_port) and self.headers.get('Origin', self.origin()) == self.origin()

        def authorized(self):
            cookie = http.cookies.SimpleCookie()
            try:
                cookie.load(self.headers.get('Cookie', ''))
                name = 'liquid_console_' + str(self.server.server_port)
                value = cookie[name].value if name in cookie else ''
            except http.cookies.CookieError:
                return False
            return hmac.compare_digest(value, token)

        def send(self, code, body, kind='application/json; charset=utf-8', extra=None):
            if not isinstance(body, bytes):
                body = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(code)
            for key, value in {'Content-Type': kind, 'Content-Length': str(len(body)), 'Cache-Control': 'no-store',
                               'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
                               'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; object-src 'none'",
                               **(extra or {})}.items():
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if not self.headers_ok():
                return self.send(403, {'error': 'Local origin required'})
            route = urlsplit(self.path)
            query = parse_qs(route.query)
            if route.path == '/' and 'token' in query:
                if not hmac.compare_digest(query['token'][0], token):
                    return self.send(401, {'error': 'Invalid launch token'})
                return self.send(303, b'', extra={'Location': '/', 'Set-Cookie': 'liquid_console_' + str(self.server.server_port) + '=' + token + '; HttpOnly; SameSite=Strict; Path=/'})
            if not self.authorized():
                return self.send(401, {'error': 'Open the private launch URL printed by the console server'})
            if route.path == '/favicon.ico':
                return self.send(204, b'', 'image/x-icon')
            if route.path in ['/', '/app.js', '/style.css']:
                name = 'index.html' if route.path == '/' else route.path[1:]
                kind = {'index.html': 'text/html', 'app.js': 'text/javascript', 'style.css': 'text/css'}[name]
                return self.send(200, (ASSETS / name).read_bytes(), kind + '; charset=utf-8')
            try:
                if route.path == '/api/state':
                    return self.send(200, {'config': console.config, 'runs': console.list_runs(), 'active': console.active,
                                          'pins': PINS, 'storage': str(console.state)})
                parts = route.path.strip('/').split('/')
                if len(parts) >= 3 and parts[:2] == ['api', 'runs']:
                    ident = parts[2]
                    path = console.directory(ident)
                    if len(parts) == 4 and parts[3] == 'cases':
                        rows = console.rows(ident)
                        search = query.get('q', [''])[0].casefold()
                        outcome = query.get('outcome', [''])[0]
                        suite = query.get('suite', [''])[0]
                        def matches(row):
                            label = 'excluded' if not row['selected'] else row['qualificationComparison']
                            return (not search or search in row['caseID'].casefold()) and (not outcome or label == outcome) and (not suite or row['suite'] == suite)
                        selected = [r for r in rows if matches(r)]
                        offset = max(0, int(query.get('offset', ['0'])[0]))
                        return self.send(200, {'total': len(selected), 'rows': selected[offset:offset + 80],
                                              'suites': sorted({r['suite'] for r in rows})})
                    if len(parts) == 4 and parts[3] == 'log':
                        file = path / 'console.log'
                        if not file.exists():
                            return self.send(200, {'text': 'Starting…'})
                        with file.open('rb') as stream:
                            stream.seek(max(0, file.stat().st_size - 65536))
                            return self.send(200, {'text': stream.read().decode('utf-8', errors='replace')})
                    if len(parts) == 5 and parts[3] == 'files':
                        files = {'log': 'console.log', 'run': 'run.json', 'receipt': 'artifacts/liquid-spec/receipt.json',
                                 'matrix': 'artifacts/liquid-spec/independent/spec/ELIGIBILITY_MATRIX.json',
                                 'ledger': 'artifacts/liquid-spec/independent/spec/PHASE_AND_DIAGNOSTIC_LEDGER.json',
                                 'summary': 'artifacts/liquid-spec/independent/spec/SPEC_RUNS.json',
                                 'trace': 'artifacts/liquid-spec/independent/spec/RPC_TRACES.jsonl'}
                        file = path / files[parts[4]]
                        if file.is_symlink() or not file.resolve().is_relative_to(path) or not file.is_file():
                            raise ValueError('Evidence is not available yet')
                        return self.send(200, file.read_bytes(), 'application/octet-stream',
                                         {'Content-Disposition': 'attachment; filename="' + file.name + '"'})
                return self.send(404, {'error': 'Unknown route'})
            except (ValueError, KeyError, OSError) as error:
                return self.send(400, {'error': str(error)})

        def do_POST(self):
            if not self.headers_ok():
                return self.send(403, {'error': 'Local origin required'})
            if not self.authorized():
                return self.send(401, {'error': 'Launch authentication required'})
            if self.headers.get('Content-Type') != 'application/json':
                return self.send(415, {'error': 'JSON required'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 32768:
                    raise ValueError('Request size outside console bound')
                value = json.loads(self.rfile.read(size))
                if not isinstance(value, dict):
                    raise ValueError('Expected a JSON object')
                if self.path == '/api/config':
                    console.save_config(value)
                    return self.send(200, {'saved': True})
                if value != {}:
                    raise ValueError('This operation accepts no parameters')
                if self.path == '/api/check':
                    return self.send(200, preflight(console.config))
                if self.path == '/api/run':
                    return self.send(202, console.start())
                parts = self.path.strip('/').split('/')
                if len(parts) == 4 and parts[:2] == ['api', 'runs'] and parts[3] == 'cancel':
                    console.cancel(parts[2])
                    return self.send(200, {'cancelRequested': True})
                return self.send(404, {'error': 'Unknown operation'})
            except (ValueError, KeyError, OSError) as error:
                return self.send(400, {'error': str(error)})
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-root', type=Path, default=Path.home() / 'Library/Application Support/Swift-Liquid/Conformance')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--spec-path', default='')
    parser.add_argument('--reference-path', default='')
    parser.add_argument('--ruby', default='/opt/homebrew/opt/ruby/bin/ruby')
    parser.add_argument('--gem-path', default=os.environ.get('GEM_PATH', ''))
    args = parser.parse_args()
    console = Console(args.state_root, {'specPath': args.spec_path, 'referencePath': args.reference_path,
                                       'rubyPath': args.ruby, 'gemPath': args.gem_path})
    token = secrets.token_urlsafe(32)
    server = ThreadingHTTPServer(('127.0.0.1', args.port), handler(console, token))
    print(json.dumps({'url': 'http://127.0.0.1:' + str(server.server_port) + '/?token=' + token,
                      'storage': str(console.state)}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        console.close()
        server.server_close()


if __name__ == '__main__':
    main()
