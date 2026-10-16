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
from test_evidence import qualify
from archive_provenance import revision as archive_revision

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
        'THIRD_PARTY_NOTICES.md', 'CONTRIBUTING.md', 'CODE_OF_CONDUCT.md', 'SECURITY.md', 'SUPPORT.md', 'RELEASING.md', 'AGENTS.md', '.gitignore', '.spi.yml']]
    for folder in ['Sources', 'Tests', 'Scripts', 'Documentation', 'Examples', 'Tools', 'Licenses', '.github']:
        paths += [p for p in (ROOT / folder).rglob('*') if p.is_file() and '.build' not in p.parts and '__pycache__' not in p.parts]
    return [{'path': str(p.relative_to(ROOT)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(paths)]

def source_revision(archive_provenance=None):
    if archive_provenance is not None:
        return archive_revision(ROOT, archive_provenance, source_snapshot())
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()
    return {'commit': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}'),
            'clean': not bool(git('status', '--porcelain'))}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lane', choices=['native', 'safety', 'docs', 'performance', 'reference', 'development', 'platforms', 'archive', 'matched-performance', 'installation', 'liquid-spec'], default='native')
    parser.add_argument('--reference-path', type=Path, help='Clean checkout of the pinned Shopify reference (reference or liquid-spec lane)')
    parser.add_argument('--spec-path', type=Path, help='Clean pinned liquid-spec checkout for the opt-in functional lane')
    parser.add_argument('--archive-provenance', type=Path,
                        help='Inspected producer archive provenance for a Git-free native export')
    args = parser.parse_args()
    if args.archive_provenance is not None and args.lane != 'native':
        parser.error('--archive-provenance is only for native qualification of a source export')
    output = ROOT / 'Artifacts' / args.lane
    output.mkdir(parents=True, exist_ok=True)
    env = environment()
    env['LIQUID_TEST_EVIDENCE_PROBE_OUTPUT'] = str(output / 'runner-probe')
    receipt = {'lane': args.lane, 'startedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'platform': platform.platform(), 'sourceRevision': source_revision(args.archive_provenance), 'sources': source_snapshot(), 'commands': [], 'status': 'failed'}

    def run(command, name, check=True):
        if command[:len(swift())] == swift() and "--version" not in command:
            flags = shlex.split(env.get("LIQUID_SWIFTPM_FLAGS", ""))
            position = len(swift()) + 1 if command[len(swift())] == "package" else len(command)
            command = command[:position] + flags + command[position:]
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
        (output / (name + '.log')).write_text(result.stdout + result.stderr)
        receipt['commands'].append({'command': command, 'exitCode': result.returncode, 'log': name + '.log'})
        if check and result.returncode:
            raise RuntimeError(f'{name} failed; see {output / (name + ".log")}')
        return result.stdout if check else result

    def run_tests(options, name, profile='full'):
        events = output / (name + '.events.jsonl')
        summary = output / (name + '.tests.json')
        events.unlink(missing_ok=True)
        summary.unlink(missing_ok=True)
        result = run(swift() + ['test', *options, '--event-stream-version', '0',
                              '--event-stream-output-path', str(events)], name, check=False)
        evidence = qualify(events, ROOT / 'Tests/TestInventory.json', profile, result.returncode)
        evidence.update(name=name, events=events.name, summary=summary.name)
        summary.write_text(json.dumps(evidence, indent=2) + '\n')
        receipt.setdefault('testLanes', []).append(evidence)
        if evidence['status'] != 'passed':
            raise RuntimeError(f'{name} failed structured admission; see {summary}')

    try:
        if env.get('GITHUB_ACTIONS') == 'true':
            receipt['runner'] = {key: env.get(key) for key in ['LIQUID_RUNNER_ENVIRONMENT', 'RUNNER_OS', 'RUNNER_ARCH', 'ImageOS', 'ImageVersion', 'GITHUB_SHA']}
            if env.get('LIQUID_RUNNER_ENVIRONMENT') != 'github-hosted':
                raise RuntimeError('CI qualification requires a GitHub-hosted runner')
        version = run(swift() + ['--version'], 'toolchain')
        receipt['toolchain'] = version.strip()
        match = re.search(r'Swift version (\d+)\.(\d+)', version)
        if not match or tuple(map(int, match.groups())) < (6, 4):
            raise RuntimeError('Swift 6.4 or later is required')
        run([sys.executable, '-B', 'Scripts/public_check.py'], 'public-check')
        if args.lane in ['native', 'development']:
            run([sys.executable, '-B', 'Scripts/check_archive_provenance.py'], 'archive-provenance-contract')
            run([sys.executable, '-B', 'Scripts/check_workflow_policy.py'], 'workflow-policy-regressions')
            run([sys.executable, '-B', 'Scripts/check_release_evidence.py'], 'release-evidence-contract')
            run([sys.executable, '-B', 'Scripts/check_test_evidence.py'], 'test-evidence-contract')
            run(swift() + ['build', '-Xswiftc', '-warnings-as-errors'], 'debug-build')
            run_tests([], 'debug-tests')
            if args.lane == 'native':
                run(swift() + ['build', '-c', 'release', '-Xswiftc', '-warnings-as-errors'], 'release-build')
                run_tests(['-c', 'release'], 'release-tests')
                for repeat in [1, 2]:
                    run_tests(['--filter', 'AdversarialTests|cancellation|suspension'],
                              f'adversarial-repeat-{repeat}', profile='adversarial')
            run(swift() + ['run', '--package-path', 'Examples/Consumer', 'LiquidConsumer'], 'consumer')
            run(swift() + ['run', '--package-path', 'Examples/FiltersConsumer', 'LiquidFiltersConsumer'], 'filters-consumer')
            run(swift() + ['run', '--package-path', 'Examples/InspectionConsumer', 'LiquidInspectionConsumer'], 'inspection-consumer')
            run(swift() + ['run', '--package-path', 'Examples/MetricsConsumer', 'LiquidMetricsConsumer'], 'metrics-consumer')
            run(swift() + ['run', '--package-path', 'Examples/DependencyConsumer', 'LiquidDependencyConsumer'], 'dependency-consumer')
            run([sys.executable, '-B', 'Scripts/check_readme_examples.py'], 'readme-consumer')
            binary_path = run(swift() + ['build', '--show-bin-path'], 'binary-path').strip().splitlines()[-1]
            run([sys.executable, '-B', 'Scripts/check_cli.py', str(Path(binary_path) / 'liquid')], 'cli')
            run([sys.executable, '-B', 'Scripts/check_dependencies.py', str(Path(binary_path) / 'liquid')], 'dependency-cli-schema')
        elif args.lane == 'installation':
            run([sys.executable, '-B', 'Scripts/check_installation.py'], 'published-installation')
        elif args.lane == 'safety':
            run_tests(['--sanitize', 'address', '--scratch-path', '.build/address'], 'address')
            run_tests(['--sanitize', 'thread', '--scratch-path', '.build/thread', '--filter', 'concurrentRenders'], 'thread', profile='thread')
        elif args.lane == 'liquid-spec':
            if not args.spec_path or not args.reference_path:
                raise RuntimeError('liquid-spec requires --spec-path and --reference-path')
            run([sys.executable, '-B', 'Scripts/check_liquid_spec.py', '--spec-path', str(args.spec_path),
                 '--reference-path', str(args.reference_path), '--output', str(output / 'independent')], 'liquid-spec')
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
            run(swift() + ['run', '-c', 'release', '--package-path', 'Tools/DependencyBenchmarks', 'LiquidDependencyBenchmarks', str(output / 'dependencies.json')], 'dependency-benchmarks')
            run(swift() + ['run', '-c', 'release', '-Xswiftc', '-warnings-as-errors', '--package-path', 'Tools/MaintenanceBenchmarks', 'LiquidMaintenanceBenchmarks', str(output / 'maintenance.json')], 'maintenance-benchmarks')
            run([sys.executable, '-B', 'Scripts/maintenance_evidence.py', str(output / 'maintenance.json')], 'maintenance-admission')
        receipt['status'] = 'passed'
    except (RuntimeError, OSError) as error:
        receipt['error'] = str(error)
    receipt['endingSourceRevision'] = source_revision(args.archive_provenance)
    receipt['sourceUnchanged'] = receipt['sources'] == source_snapshot() and receipt['sourceRevision'] == receipt['endingSourceRevision']
    receipt['sourceQualified'] = receipt['sourceUnchanged'] and receipt['sourceRevision']['clean']
    if not receipt['sourceUnchanged']:
        receipt.update(status='failed', error='Source changed during qualification')
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    display = {k: v for k, v in receipt.items() if k not in ['sources', 'commands']}
    if 'testLanes' in display:
        display['testLanes'] = [{k: v for k, v in lane.items() if k != 'functions'} for lane in display['testLanes']]
    print(json.dumps(display, indent=2))
    return 0 if receipt['status'] == 'passed' else 1

if __name__ == '__main__':
    sys.exit(main())
