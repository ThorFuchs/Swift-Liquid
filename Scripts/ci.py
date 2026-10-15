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
    paths = [ROOT / name for name in ['Package.swift', 'README.md', 'CHANGELOG.md', 'LICENSE', 'NOTICE',
        'THIRD_PARTY_NOTICES.md', 'CONTRIBUTING.md', 'SECURITY.md', 'SUPPORT.md', 'RELEASING.md', 'AGENTS.md', '.gitignore']]
    for folder in ['Sources', 'Tests', 'Scripts', 'Documentation', 'Examples', 'Tools', 'Licenses', '.github']:
        paths += [p for p in (ROOT / folder).rglob('*') if p.is_file() and '.build' not in p.parts and '__pycache__' not in p.parts]
    return [{'path': str(p.relative_to(ROOT)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(paths)]

def require_fixtures(log):
    for label, count in [('Golden Liquid', 1098), ('Native compatibility probes', 221),
                         ('Ruby date grammar', 337), ('Public date parsing', 376),
                         ('Custom filter reference cases', 15), ('AST inspection cases', 8)]:
        if not re.search(rf'{label}.*{count} test cases passed', log):
            raise RuntimeError(f'Missing complete {label} run ({count} cases)')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lane', choices=['native', 'safety', 'docs', 'performance', 'reference', 'development', 'platforms', 'archive', 'matched-performance'], default='native')
    parser.add_argument('--reference-path', type=Path, help='Clean checkout of the pinned Shopify reference (reference lane only)')
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
        if args.lane in ['native', 'development']:
            run(swift() + ['build', '-Xswiftc', '-warnings-as-errors'], 'debug-build')
            run(swift() + ['test'], 'debug-tests')
            test_names = ['debug-tests']
            if args.lane == 'native':
                run(swift() + ['build', '-c', 'release', '-Xswiftc', '-warnings-as-errors'], 'release-build')
                run(swift() + ['test', '-c', 'release'], 'release-tests')
                test_names.append('release-tests')
            receipt['testLanes'] = []
            for name in test_names:
                log = (output / (name + '.log')).read_text()
                require_fixtures(log)
                summary = re.search(r'Test run with (\d+) tests .* passed', log)
                if not summary or int(summary.group(1)) < 54:
                    raise RuntimeError(f'{name} has an absent or reduced test run')
                receipt['testLanes'].append({'name': name, 'goldenCases': 1098, 'compatibilityProbes': 221,
                    'grammarCases': 337, 'dateFilterCases': 376, 'outsideSupportedYears': 35,
                    'hostExtensionCases': 15, 'inspectionCases': 8, 'testFunctions': int(summary.group(1)), 'skipped': 0})
            run(swift() + ['run', '--package-path', 'Examples/Consumer', 'LiquidConsumer'], 'consumer')
            run(swift() + ['run', '--package-path', 'Examples/FiltersConsumer', 'LiquidFiltersConsumer'], 'filters-consumer')
            run(swift() + ['run', '--package-path', 'Examples/InspectionConsumer', 'LiquidInspectionConsumer'], 'inspection-consumer')
            run(swift() + ['run', '--package-path', 'Examples/MetricsConsumer', 'LiquidMetricsConsumer'], 'metrics-consumer')
            binary_path = run(swift() + ['build', '--show-bin-path'], 'binary-path').strip().splitlines()[-1]
            run([sys.executable, '-B', 'Scripts/check_cli.py', str(Path(binary_path) / 'liquid')], 'cli')
        elif args.lane == 'safety':
            run(swift() + ['test', '--sanitize', 'address', '--scratch-path', '.build/address'], 'address')
            run(swift() + ['test', '--sanitize', 'thread', '--scratch-path', '.build/thread', '--filter', 'concurrentRenders'], 'thread')
            require_fixtures((output / 'address.log').read_text())
            if not re.search(r'Test run with 4 tests .* passed', (output / 'thread.log').read_text()):
                raise RuntimeError('ThreadSanitizer did not execute core, filter, inspection and metrics concurrency tests')
        elif args.lane == 'reference':
            if not args.reference_path:
                raise RuntimeError('The reference lane requires --reference-path to a clean pinned checkout')
            run(['ruby', '-I', str(args.reference_path.resolve() / 'lib'), 'Scripts/check_reference.rb', str(output / 'reference.json')], 'reference')
        elif args.lane == 'docs':
            run([sys.executable, '-B', 'Scripts/build_documentation.py'], 'documentation')
        elif args.lane == 'platforms':
            run([sys.executable, '-B', 'Scripts/check_platforms.py'], 'platforms')
        elif args.lane == 'matched-performance':
            run([sys.executable, '-B', 'Scripts/compare_benchmarks.py'], 'matched-benchmarks')
        elif args.lane == 'archive':
            run([sys.executable, '-B', 'Scripts/check_archive.py'], 'archive')
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
