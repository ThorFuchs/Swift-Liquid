#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Bounded 1.3.1 interpolation hypotheses; preserve all checkpoints and observations."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import shutil
import sys
import statistics
import tempfile
from compare_benchmarks import (ROOT, OUTPUT, ENV, COMMANDS, HARNESS, HARNESS_SHA256,
    MANIFEST_SHA256, run, git, extract, library_hash, index_records, comparisons)

SOURCE = 'fb81cf4ff01f1bf098ceb5fff65638b1271294e0'
EXPECTED = '50b372f97e4f3429647723b7c9ec8c4b8cca13759774fa069b369109b48fafa4'
HARNESS_SOURCE = '9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e'
CANDIDATE = '65f66404e2ad1e62862d22db12c8c5a59001635b'
CANDIDATE_EXPECTED = '6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a'


def main():
    harness = git('show', HARNESS_SOURCE + ':' + HARNESS)
    manifest = git('show', HARNESS_SOURCE + ':Tools/Benchmarks/Package.swift')
    assert hashlib.sha256(harness).hexdigest() == HARNESS_SHA256
    assert hashlib.sha256(manifest).hexdigest() == MANIFEST_SHA256
    marker = '    static func main() async throws {\n'
    assert harness.decode().count(marker) == 1
    generic = harness.decode().replace(marker,
        '    static func main() async throws { try await runOnGenericExecutor() }\n\n'
        '    @concurrent\n    private static func runOnGenericExecutor() async throws {\n').encode()
    generic_manifest = manifest.replace(b'"LiquidBenchmarks"', b'"LiquidGenericBenchmarks"')
    (OUTPUT / 'generic-harness.swift').write_bytes(generic)
    (OUTPUT / 'generic-manifest.swift').write_bytes(generic_manifest)
    metadata = {'operation': 'synchronous-interpolation-followup', 'candidateCommit': CANDIDATE, 'candidateLibrarySHA256': CANDIDATE_EXPECTED, 'sourceCommit': SOURCE,
        'baselineVersion': '1.3.1', 'expectedLibrarySHA256': EXPECTED,
        'harnessSourceCommit': HARNESS_SOURCE, 'harnessSHA256': HARNESS_SHA256,
        'manifestSHA256': MANIFEST_SHA256,
        'genericHarnessSHA256': hashlib.sha256(generic).hexdigest(),
        'genericManifestSHA256': hashlib.sha256(generic_manifest).hexdigest(),
        'toolchain': run(['xcrun', 'swift', '--version'], 'toolchain'),
        'platform': platform.platform(), 'logicalCPUs': os.cpu_count(),
        'runnerEnvironment': ENV.get('LIQUID_RUNNER_ENVIRONMENT'),
        'commands': COMMANDS, 'phases': {}, 'sourceManifests': {},
        'correctnessScope': 'Every timed output/checksum is checked. No checkpoint removed. Full regression qualification is required before adopting a variant.'}
    assert metadata['runnerEnvironment'] == 'github-hosted'
    metadata['hardware'] = {key: run(['sysctl', '-n', key], 'host-' + key.replace('.', '-'))
        for key in ['hw.model', 'hw.physicalcpu', 'hw.memsize', 'machdep.cpu.brand_string']}
    with tempfile.TemporaryDirectory(prefix='liquid-interpolation-study-') as tmp:
        qualification = Path(tmp) / 'qualification'
        run(['git', 'worktree', 'add', '--detach', str(qualification), CANDIDATE], 'candidate-qualification-checkout')
        assert library_hash(qualification) == CANDIDATE_EXPECTED
        try:
            run([sys.executable, '-B', 'Scripts/ci.py', '--lane', 'development'],
                'candidate-development', cwd=qualification)
        finally:
            retained = qualification / 'Artifacts/development'
            if retained.exists(): shutil.copytree(retained, OUTPUT / 'candidate-development')
        receipt = json.loads((OUTPUT / 'candidate-development/receipt.json').read_text())
        assert receipt['status'] == 'passed'
        tests = receipt['testLanes'][0]
        assert tests['testFunctions'] == 78 and tests['completedCases'] == 2166
        metadata['developmentQualification'] = {'status': 'passed', 'sourceCommit': CANDIDATE,
            'workflowCommit': ENV.get('GITHUB_SHA'), 'functions': tests['testFunctions'],
            'parameterCases': tests['completedCases'], 'receipt': 'candidate-development/receipt.json'}
        run(['git', 'worktree', 'remove', '--force', str(qualification)], 'candidate-qualification-cleanup')
        binaries = {}; hashes = {}; cancellation_counts = {}
        for name in ['baselineA', 'candidate', 'baselineB']:
            root = Path(tmp) / name / 'Swift-Liquid'; root.mkdir(parents=True)
            extract(CANDIDATE if name == 'candidate' else SOURCE, root)
            assert library_hash(root) == (CANDIDATE_EXPECTED if name == 'candidate' else EXPECTED)
            if name == 'candidate':
                assert (root / 'Sources/Liquid/LiquidLimits.swift').read_bytes() == git('show', SOURCE + ':Sources/Liquid/LiquidLimits.swift')
                (OUTPUT / 'candidate-core.diff').write_bytes(git('diff', SOURCE, CANDIDATE, '--', 'Sources/Liquid'))
            hashes[name] = library_hash(root)
            cancellation_counts[name] = sum(p.read_text().count('Task.checkCancellation()')
                for p in (root / 'Sources/Liquid').rglob('*.swift'))
            metadata['sourceManifests'][name] = [{'path': str(p.relative_to(root)),
                'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                for p in sorted((root / 'Sources/Liquid').rglob('*.swift'))]
            (root / HARNESS).write_bytes(harness)
            (root / 'Tools/Benchmarks/Package.swift').write_bytes(manifest)
            probe = root / 'Tools/GenericBenchmarks'
            (probe / 'Sources/LiquidGenericBenchmarks').mkdir(parents=True)
            (probe / 'Package.swift').write_bytes(generic_manifest)
            (probe / 'Sources/LiquidGenericBenchmarks/main.swift').write_bytes(generic)
            flags = shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS', ''))
            for driver, package, product in [('common', root / 'Tools/Benchmarks', 'LiquidBenchmarks'),
                                              ('generic', probe, 'LiquidGenericBenchmarks')]:
                run(['xcrun', 'swift', 'build', '-c', 'release', '--package-path', str(package),
                    *flags], name + '-' + driver + '-build')
                location = run(['xcrun', 'swift', 'build', '-c', 'release', '--package-path',
                    str(package), '--show-bin-path', *flags], name + '-' + driver + '-binary')
                binaries[name, driver] = str(Path(location.splitlines()[-1]) / product)
            run(['xcrun', 'nm', '-n', binaries[name, 'common']], name + '-symbols')
            run(['xcrun', 'otool', '-tvV', binaries[name, 'common']], name + '-assembly')
        assert hashes['baselineA'] == hashes['baselineB'] == EXPECTED
        assert hashes['candidate'] == CANDIDATE_EXPECTED != EXPECTED
        assert cancellation_counts['baselineA'] == cancellation_counts['baselineB']
        assert cancellation_counts['candidate'] == cancellation_counts['baselineA'] + 1
        metadata['librarySHA256'] = hashes; metadata['cancellationCheckpointCounts'] = cancellation_counts
        for block in range(1, 4):
            for hypothesis, variant in [('candidate', 'candidate'), ('identical', 'baselineB')]:
                for driver in ['common', 'generic']:
                    phase_name = hypothesis + '-' + driver
                    phase = metadata['phases'].setdefault(phase_name, {'runs': [],
                        'labels': ['baselineA', variant], 'driver': driver})
                    for position, label in enumerate(['baselineA', variant, variant, 'baselineA']):
                        name = f'{phase_name}-{block}-{position + 1}-{label}'
                        destination = OUTPUT / (name + '.json'); load = os.getloadavg()
                        run([binaries[label, driver], str(destination)], name)
                        index_records(json.loads(destination.read_text()))
                        phase['runs'].append({'name': name, 'version': label, 'result': destination.name,
                            'block': block, 'loadAverageBefore': load, 'loadAverageAfter': os.getloadavg()})
    for phase in metadata['phases'].values():
        records = {r['name']: index_records(json.loads((OUTPUT / r['result']).read_text()))
                   for r in phase['runs']}
        phase['comparisons'] = comparisons(phase['runs'], records, phase['labels'])
        phase['reviewRequired'] = [r['name'] + '/' + r['mode'] for r in phase['comparisons'] if r['requiresReview']]
        phase['varianceReviewRequired'] = [r['name'] + '/' + r['mode'] for r in phase['comparisons'] if r['varianceRequiresReview']]
        for row in phase['comparisons']:
            key = row['name'], row['mode']; effects = []
            for block in range(1, 4):
                values = {label: [records[r['name']][key]['medianNanoseconds'] for r in phase['runs']
                    if r['block'] == block and r['version'] == label] for label in phase['labels']}
                effects.append((statistics.median(values[phase['labels'][1]]) /
                                statistics.median(values[phase['labels'][0]]) - 1) * 100)
            row['blockChangesPercent'] = effects
    metadata['status'] = 'measured'
    (OUTPUT / 'interpolation-study.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps({name: {'flags': p['reviewRequired'], 'spread': p['varianceReviewRequired']}
                      for name, p in metadata['phases'].items()}, indent=2))


if __name__ == '__main__':
    main()
