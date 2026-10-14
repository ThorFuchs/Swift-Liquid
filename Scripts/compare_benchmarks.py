#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare two immutable library trees with the pinned 1.0.0 harness on one host."""
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shlex
import statistics
import subprocess
import tarfile
import tempfile
from ci import ROOT, environment, swift

BASELINE = 'd36018e6b6822ae408a6c1c439c2307484525b7b'
HARNESS = 'Tools/Benchmarks/Sources/LiquidBenchmarks/main.swift'
HARNESS_SHA256 = 'd54696ca5ec336b83ad6510737c7bd29382192e81bc17b6cd61a6e22a9d13097'
OUTPUT = ROOT / 'Artifacts/matched-performance'
OUTPUT.mkdir(parents=True, exist_ok=True)
ENV = environment()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def run(command, name, cwd=ROOT):
    result = subprocess.run(command, cwd=cwd, env=ENV, capture_output=True, text=True)
    (OUTPUT / (name + '.log')).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'{name} failed; see {OUTPUT / (name + ".log")}')
    return result.stdout.strip()


def extract(commit, destination):
    with tarfile.open(fileobj=io.BytesIO(git('archive', '--format=tar', commit))) as archive:
        for member in archive.getmembers():
            if member.issym() or member.islnk() or Path(member.name).is_absolute() or '..' in Path(member.name).parts:
                raise RuntimeError(f'Unsafe tracked archive entry: {member.name}')
        archive.extractall(destination)


def library_hash(root):
    digest = hashlib.sha256()
    for path in sorted((root / 'Sources/Liquid').rglob('*.swift')):
        digest.update(str(path.relative_to(root)).encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def index_records(result):
    if result.get('configuration') != 'release':
        raise RuntimeError('Comparison requires release-mode results')
    records = {(r['name'], r['mode']): r for r in result['workloads']}
    expected = {(name, mode) for name in ['interpolation', 'filter-chain', 'loop', 'partial', 'date']
                for mode in ['parse-and-render', 'reused-template']}
    if len(result['workloads']) != 10 or set(records) != expected:
        raise RuntimeError('Missing or duplicate original benchmark records')
    for record in records.values():
        if (record['samples'], record['warmupSamples'], record['repetitionsPerSample']) != (25, 10, 100):
            raise RuntimeError('Original sample policy changed')
        for field in ['medianNanoseconds', 'p95Nanoseconds', 'minimumNanoseconds', 'maximumNanoseconds']:
            if not 0 < record[field] < float('inf'):
                raise RuntimeError('Invalid benchmark timing')
    return records


def main():
    if git('status', '--porcelain').strip():
        raise RuntimeError('Matched qualification requires a clean candidate commit')
    candidate = git('rev-parse', 'HEAD').decode().strip()
    baseline = git('rev-parse', BASELINE + '^{commit}').decode().strip()
    if baseline != BASELINE:
        raise RuntimeError('Baseline commit identity changed')
    harness = git('show', BASELINE + ':' + HARNESS)
    if hashlib.sha256(harness).hexdigest() != HARNESS_SHA256:
        raise RuntimeError('Pinned common harness changed')
    manifest = git('show', BASELINE + ':Tools/Benchmarks/Package.swift')
    toolchain = run(swift() + ['--version'], 'toolchain')
    metadata = {'schemaVersion': 1, 'baselineCommit': BASELINE, 'candidateCommit': candidate,
                'harnessSHA256': HARNESS_SHA256, 'manifestSHA256': hashlib.sha256(manifest).hexdigest(),
                'toolchain': toolchain, 'platform': platform.platform(), 'architecture': platform.machine(),
                'logicalCPUs': os.cpu_count(), 'order': ['baseline', 'candidate', 'candidate', 'baseline'] * 3,
                'protocol': 'Build both first; three sequential ABBA blocks; six runs per version; median of run medians.',
                'reviewThresholdPercent': 10, 'runs': []}
    if platform.system() == 'Darwin':
        metadata['hardware'] = {key: run(['sysctl', '-n', key], 'host-' + key.replace('.', '-'))
                                for key in ['hw.model', 'hw.physicalcpu', 'hw.memsize', 'machdep.cpu.brand_string']}
    with tempfile.TemporaryDirectory(prefix='swift-liquid-matched-') as temporary:
        binaries = {}
        for label, commit in [('baseline', BASELINE), ('candidate', candidate)]:
            root = Path(temporary) / label / 'Swift-Liquid'
            root.mkdir(parents=True)
            extract(commit, root)
            (root / HARNESS).write_bytes(harness)
            (root / 'Tools/Benchmarks/Package.swift').write_bytes(manifest)
            metadata[label + 'LibrarySHA256'] = library_hash(root)
            package = str(root / 'Tools/Benchmarks')
            flags = shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS', ''))
            run(swift() + ['build', '-c', 'release', '--package-path', package, *flags], label + '-build')
            location = run(swift() + ['build', '-c', 'release', '--package-path', package, '--show-bin-path', *flags], label + '-binary')
            binaries[label] = str(Path(location.splitlines()[-1]) / 'LiquidBenchmarks')
        # No builds occur during measurement; all processes execute serially on this host.
        for index, label in enumerate(metadata['order']):
            name = f'{index + 1:02d}-{label}'
            destination = OUTPUT / (name + '.json')
            before = os.getloadavg()
            run([binaries[label], str(destination)], name)
            result = json.loads(destination.read_text())
            index_records(result)
            metadata['runs'].append({'name': name, 'version': label, 'result': destination.name,
                                     'loadAverageBefore': before, 'loadAverageAfter': os.getloadavg()})
    all_records = {r['name']: index_records(json.loads((OUTPUT / r['result']).read_text())) for r in metadata['runs']}
    reference = all_records[metadata['runs'][0]['name']]
    comparisons = []
    for key, expected in sorted(reference.items()):
        measurements = {'baseline': [], 'candidate': []}
        for run_info in metadata['runs']:
            record = all_records[run_info['name']][key]
            for field in ['outputBytes', 'fnv1aChecksum', 'samples', 'warmupSamples', 'repetitionsPerSample']:
                if record[field] != expected[field]:
                    raise RuntimeError(f'Output or sample mismatch: {key}, {field}')
            measurements[run_info['version']].append(record['medianNanoseconds'])
        baseline_median = statistics.median(measurements['baseline'])
        candidate_median = statistics.median(measurements['candidate'])
        change = (candidate_median / baseline_median - 1) * 100
        comparisons.append({'name': key[0], 'mode': key[1], 'baselineMedianNanoseconds': baseline_median,
                            'candidateMedianNanoseconds': candidate_median, 'medianChangePercent': change,
                            'baselineRunMedians': measurements['baseline'], 'candidateRunMedians': measurements['candidate'],
                            'outputBytes': expected['outputBytes'], 'fnv1aChecksum': expected['fnv1aChecksum'],
                            'requiresReview': abs(change) >= 10})
    metadata['comparisons'] = comparisons
    metadata['reviewRequired'] = [r['name'] + '/' + r['mode'] for r in comparisons if r['requiresReview']]
    metadata['status'] = 'measured'
    (OUTPUT / 'comparison.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps({'baselineCommit': BASELINE, 'candidateCommit': candidate, 'runs': len(metadata['runs']),
                      'recordsCompared': len(comparisons), 'reviewRequired': metadata['reviewRequired']}, indent=2))


if __name__ == '__main__':
    main()
