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
import statistics
import tempfile
from compare_benchmarks import (ROOT, OUTPUT, ENV, COMMANDS, HARNESS, HARNESS_SHA256,
    MANIFEST_SHA256, run, git, extract, library_hash, index_records, comparisons)

SOURCE = 'fb81cf4ff01f1bf098ceb5fff65638b1271294e0'
EXPECTED = '50b372f97e4f3429647723b7c9ec8c4b8cca13759774fa069b369109b48fafa4'
HARNESS_SOURCE = '9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e'


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
    metadata = {'operation': 'interpolation-investigation', 'sourceCommit': SOURCE,
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
        binaries = {}; hashes = {}; cancellation_counts = {}
        for name in ['baselineA', 'nativeString', 'inlineOutput', 'baselineB']:
            root = Path(tmp) / name / 'Swift-Liquid'; root.mkdir(parents=True)
            extract(SOURCE, root)
            assert library_hash(root) == EXPECTED
            changes = []
            if name == 'nativeString':
                path = root / 'Sources/Liquid/Rendering/Renderer+Utilities.swift'
                before = path.read_text(); after = before
                for function in ['stringifyUnescapedPreservingSafeHTML', 'stringifyUnescaped']:
                    header = f'    internal func {function}(_ value: Any) -> String {{\n'
                    assert after.count(header) == 1
                    after = after.replace(header, header +
                        '        if type(of: value) == String.self, let text = value as? String { return text }\n')
                path.write_text(after); changes.append((path, before, after))
            elif name == 'inlineOutput':
                path = root / 'Sources/Liquid/LiquidLimits.swift'
                before = path.read_text(); marker = '    func output(_ text: String) throws {\n'
                assert before.count(marker) == 1
                after = before.replace(marker, '    @inline(__always)\n' + marker)
                path.write_text(after); changes.append((path, before, after))
            if changes:
                (OUTPUT / (name + '.diff')).write_text(''.join(''.join(difflib.unified_diff(
                    before.splitlines(True), after.splitlines(True),
                    fromfile='1.3.1/' + str(path.relative_to(root)),
                    tofile=name + '/' + str(path.relative_to(root)))) for path, before, after in changes))
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
        assert hashes['nativeString'] != EXPECTED and hashes['inlineOutput'] != EXPECTED
        assert len(set(cancellation_counts.values())) == 1
        metadata['librarySHA256'] = hashes; metadata['cancellationCheckpointCounts'] = cancellation_counts
        for block in range(1, 4):
            for hypothesis, variant in [('nativeString', 'nativeString'), ('inlineOutput', 'inlineOutput'),
                                         ('identical', 'baselineB')]:
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
