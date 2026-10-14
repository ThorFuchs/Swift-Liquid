#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Run public qualification lanes and retain actual source/environment receipts."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def environment():
    env = os.environ.copy()
    if sys.platform == 'darwin' and not env.get('DEVELOPER_DIR'):
        selected = subprocess.run(['xcode-select', '-p'], capture_output=True, text=True).stdout.strip()
        if selected.endswith('CommandLineTools'):
            for candidate in ['/Applications/Xcode_27.2.app', '/Applications/Xcode-beta.app']:
                if Path(candidate).exists():
                    env['DEVELOPER_DIR'] = candidate + '/Contents/Developer'
                    break
    cache = ROOT / '.build/module-cache'
    cache.mkdir(parents=True, exist_ok=True)
    env['CLANG_MODULE_CACHE_PATH'] = str(cache)
    env['SWIFTPM_MODULECACHE_OVERRIDE'] = str(cache)
    env['TZ'] = 'UTC'
    return env

def swift():
    return ['xcrun', 'swift'] if sys.platform == 'darwin' else ['swift']

def source_snapshot():
    paths = [ROOT / 'Package.swift']
    for folder in ['Sources', 'Tests', 'Scripts', 'Documentation', 'Examples', 'Tools']:
        paths += [p for p in (ROOT / folder).rglob('*') if p.is_file() and '.build' not in p.parts and '__pycache__' not in p.parts]
    return [{'path': str(p.relative_to(ROOT)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(paths)]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lane', choices=['native', 'safety', 'docs', 'performance'], default='native')
    args = parser.parse_args()
    output = ROOT / 'Artifacts' / args.lane
    output.mkdir(parents=True, exist_ok=True)
    env = environment()
    receipt = {'lane': args.lane, 'startedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'platform': platform.platform(), 'sources': source_snapshot(), 'commands': [], 'status': 'failed'}

    def run(command, name):
        if command[:len(swift())] == swift() and "--version" not in command:
            flags = shlex.split(env.get("LIQUID_SWIFTPM_FLAGS", ""))
            position = len(swift()) + 1 if command[len(swift())] == "package" else len(command)
            command = command[:position] + flags + command[position:]
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
        (output / (name + '.log')).write_text(result.stdout + result.stderr)
        receipt['commands'].append({'command': command, 'exitCode': result.returncode, 'log': name + '.log'})
        if result.returncode:
            raise RuntimeError(f'{name} failed; see {output / (name + ".log")}')
        return result.stdout

    try:
        version = run(swift() + ['--version'], 'toolchain')
        receipt['toolchain'] = version.strip()
        match = re.search(r'Swift version (\d+)\.(\d+)', version)
        if not match or tuple(map(int, match.groups())) < (6, 4):
            raise RuntimeError('Swift 6.4 or later is required')
        run([sys.executable, '-B', 'Scripts/public_check.py'], 'public-check')
        if args.lane == 'native':
            run(swift() + ['build', '-Xswiftc', '-warnings-as-errors'], 'debug-build')
            run(swift() + ['build', '-c', 'release', '-Xswiftc', '-warnings-as-errors'], 'release-build')
            run(swift() + ['test'], 'debug-tests')
            run(swift() + ['test', '-c', 'release'], 'release-tests')
            receipt['testLanes'] = []
            for name in ['debug-tests', 'release-tests']:
                log = (output / (name + '.log')).read_text()
                if not re.search(r'Golden Liquid.*1098 test cases passed', log):
                    raise RuntimeError(f'{name} did not report all 1098 passing golden cases')
                if not re.search(r'Native compatibility probes.*63 test cases passed', log):
                    raise RuntimeError(f'{name} did not report all 63 passing compatibility probes')
                summary = re.search(r'Test run with (\d+) tests .* passed', log)
                if not summary or int(summary.group(1)) < 21:
                    raise RuntimeError(f'{name} has an absent or reduced test run')
                receipt['testLanes'].append({'name': name, 'goldenCases': 1098, 'compatibilityProbes': 63, 'testFunctions': int(summary.group(1)), 'skipped': 0})
            run(swift() + ['run', '--package-path', 'Examples/Consumer', 'LiquidConsumer'], 'consumer')
            binary_path = run(swift() + ['build', '--show-bin-path'], 'binary-path').strip().splitlines()[-1]
            run([sys.executable, '-B', 'Scripts/check_cli.py', str(Path(binary_path) / 'liquid')], 'cli')
        elif args.lane == 'safety':
            run(swift() + ['test', '--sanitize', 'address', '--scratch-path', '.build/address'], 'address')
            run(swift() + ['test', '--sanitize', 'thread', '--scratch-path', '.build/thread', '--filter', 'concurrentRenders'], 'thread')
            if not re.search(r'Golden Liquid.*1098 test cases passed', (output / 'address.log').read_text()):
                raise RuntimeError('AddressSanitizer did not execute the complete corpus')
            if not re.search(r'Test run with 1 test .* passed', (output / 'thread.log').read_text()):
                raise RuntimeError('ThreadSanitizer did not execute the concurrency test')
        elif args.lane == 'docs':
            run([sys.executable, '-B', 'Scripts/build_documentation.py'], 'documentation')
        else:
            run(swift() + ['run', '-c', 'release', '--package-path', 'Tools/Benchmarks', 'LiquidBenchmarks', str(output / 'benchmarks.json')], 'benchmarks')
        receipt['status'] = 'passed'
    except (RuntimeError, OSError) as error:
        receipt['error'] = str(error)
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: v for k, v in receipt.items() if k not in ['sources', 'commands']}, indent=2))
    return 0 if receipt['status'] == 'passed' else 1

if __name__ == '__main__':
    sys.exit(main())
