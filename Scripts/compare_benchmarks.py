#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare the pinned 1.1.0 harness and opt-in metrics with serial ABBA runs."""
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

BASELINE = '1107ec865b9ae7ed35e1245386ba882db3abd93d'
HARNESS = 'Tools/Benchmarks/Sources/LiquidBenchmarks/main.swift'
HARNESS_SHA256 = 'cdaa1ce76d114eb12ef163a8e5445704a7da6ae5563a17abffd6de5c2d2de77f'
MANIFEST_SHA256 = 'aaf1bad0e6c4c7165b35320bf95878a2a3ac20a5efa9362066901ac9836b4439'
RENDER_NAMES = ['interpolation', 'filter-chain', 'loop', 'partial', 'date', 'custom-filter']
OUTPUT = ROOT / 'Artifacts/matched-performance'
OUTPUT.mkdir(parents=True, exist_ok=True)
ENV = environment()
COMMANDS = []


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def run(command, name, cwd=ROOT, required=True):
    result = subprocess.run(command, cwd=cwd, env=ENV, capture_output=True, text=True)
    (OUTPUT / (name + '.log')).write_text(result.stdout + result.stderr)
    COMMANDS.append({'name': name, 'command': command, 'exitCode': result.returncode})
    if result.returncode and required:
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


def index_records(result, metrics_mode=None):
    if result.get('configuration') != 'release':
        raise RuntimeError('Comparison requires release-mode results')
    suffix = '-metrics' if metrics_mode == 'metrics' else ''
    records = {(r['name'], r['mode'].removesuffix(suffix) if suffix else r['mode']): r for r in result['workloads']}
    expected = {(name, mode) for name in RENDER_NAMES
                for mode in ['parse-and-render', 'reused-template']}
    if metrics_mode is None:
        expected |= {('inspection', 'parse-and-inspect'), ('inspection', 'inspect-reused-template')}
    elif result.get('renderMode') != metrics_mode:
        raise RuntimeError('Incorrect candidate metrics benchmark mode')
    if len(result['workloads']) != len(expected) or set(records) != expected:
        raise RuntimeError('Missing or duplicate benchmark records')
    for record in records.values():
        if (record['samples'], record['warmupSamples'], record['repetitionsPerSample']) != (25, 10, 100):
            raise RuntimeError('Original sample policy changed')
        for field in ['medianNanoseconds', 'p95Nanoseconds', 'minimumNanoseconds', 'maximumNanoseconds']:
            if not 0 < record[field] < float('inf'):
                raise RuntimeError('Invalid benchmark timing')
        if metrics_mode is not None:
            if not record['mode'].endswith(suffix) or (not suffix and record['mode'].endswith('-metrics')):
                raise RuntimeError('Incorrect metrics record mode')
            samples = record.get('sampleNanoseconds', [])
            if len(samples) != 25 or any(not 0 < sample < float('inf') for sample in samples):
                raise RuntimeError('Missing or invalid retained samples')
    return records


def comparisons(runs, indexed, labels):
    reference = indexed[runs[0]['name']]
    rows = []
    for key, expected in sorted(reference.items()):
        measurements = {label: [] for label in labels}
        for run_info in runs:
            record = indexed[run_info['name']][key]
            for field in ['outputBytes', 'fnv1aChecksum', 'samples', 'warmupSamples', 'repetitionsPerSample']:
                if record[field] != expected[field]:
                    raise RuntimeError(f'Output or sample mismatch: {key}, {field}')
            measurements[run_info['version']].append(record['medianNanoseconds'])
        first = statistics.median(measurements[labels[0]])
        second = statistics.median(measurements[labels[1]])
        change = (second / first - 1) * 100
        rows.append({'name': key[0], 'mode': key[1], labels[0] + 'MedianNanoseconds': first,
                     labels[1] + 'MedianNanoseconds': second, 'medianChangePercent': change,
                     labels[0] + 'RunMedians': measurements[labels[0]], labels[1] + 'RunMedians': measurements[labels[1]],
                     'outputBytes': expected['outputBytes'], 'fnv1aChecksum': expected['fnv1aChecksum'],
                     'requiresReview': abs(change) >= 10})
    return rows


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
    if hashlib.sha256(manifest).hexdigest() != MANIFEST_SHA256:
        raise RuntimeError('Pinned benchmark manifest changed')
    toolchain = run(swift() + ['--version'], 'toolchain')
    metadata = {'schemaVersion': 2, 'baselineVersion': '1.1.0', 'baselineCommit': BASELINE, 'candidateCommit': candidate,
                'harnessSHA256': HARNESS_SHA256, 'manifestSHA256': hashlib.sha256(manifest).hexdigest(),
                'toolchain': toolchain, 'platform': platform.platform(), 'architecture': platform.machine(),
                'logicalCPUs': os.cpu_count(), 'swiftPMFlags': shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS', '')),
                'developerDirectory': ENV.get('DEVELOPER_DIR'), 'commands': COMMANDS, 'order': ['baseline', 'candidate', 'candidate', 'baseline'] * 3,
                'protocol': 'Build both first; three sequential ABBA blocks; six runs per version; median of run medians.',
                'reviewThresholdPercent': 10, 'runs': []}
    if platform.system() == 'Darwin':
        metadata['hardware'] = {key: run(['sysctl', '-n', key], 'host-' + key.replace('.', '-'), required=False) or 'unavailable'
                                for key in ['hw.model', 'hw.physicalcpu', 'hw.memsize', 'machdep.cpu.brand_string']}
    with tempfile.TemporaryDirectory(prefix='swift-liquid-matched-') as temporary:
        binaries = {}
        for label, commit in [('baseline', BASELINE), ('candidate', candidate), ('candidate-metrics', candidate)]:
            root = Path(temporary) / label / 'Swift-Liquid'
            root.mkdir(parents=True)
            extract(commit, root)
            if label != 'candidate-metrics':
                (root / HARNESS).write_bytes(harness)
            else:
                metadata['metricsHarnessSHA256'] = hashlib.sha256((root / HARNESS).read_bytes()).hexdigest()
            (root / 'Tools/Benchmarks/Package.swift').write_bytes(manifest)
            metadata[label + 'LibrarySHA256'] = library_hash(root)
            package = str(root / 'Tools/Benchmarks')
            flags = shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS', ''))
            run(swift() + ['build', '-c', 'release', '--package-path', package, *flags], label + '-build')
            location = run(swift() + ['build', '-c', 'release', '--package-path', package, '--show-bin-path', *flags], label + '-binary')
            binaries[label] = str(Path(location.splitlines()[-1]) / 'LiquidBenchmarks')
        if metadata['candidate-metricsLibrarySHA256'] != metadata['candidateLibrarySHA256']:
            raise RuntimeError('Metrics comparison uses a different candidate library')
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
        metrics = {'candidateCommit': candidate, 'librarySHA256': metadata['candidateLibrarySHA256'],
                   'harnessSHA256': metadata['metricsHarnessSHA256'], 'reviewThresholdPercent': 10,
                   'order': ['ordinary', 'metrics', 'metrics', 'ordinary'] * 3, 'runs': [],
                   'protocol': 'Same candidate binary; three serial ABBA blocks; six runs per mode; externally timed calls.'}
        for index, mode in enumerate(metrics['order']):
            name = f'metrics-{index + 1:02d}-{mode}'
            destination = OUTPUT / (name + '.json')
            before = os.getloadavg()
            run([binaries['candidate-metrics'], str(destination), '--render-mode', mode], name)
            index_records(json.loads(destination.read_text()), mode)
            metrics['runs'].append({'name': name, 'version': mode, 'result': destination.name,
                                    'loadAverageBefore': before, 'loadAverageAfter': os.getloadavg()})
    all_records = {r['name']: index_records(json.loads((OUTPUT / r['result']).read_text())) for r in metadata['runs']}
    metadata['comparisons'] = comparisons(metadata['runs'], all_records, ['baseline', 'candidate'])
    metadata['reviewRequired'] = [r['name'] + '/' + r['mode'] for r in metadata['comparisons'] if r['requiresReview']]
    metric_records = {r['name']: index_records(json.loads((OUTPUT / r['result']).read_text()), r['version']) for r in metrics['runs']}
    common = all_records[metadata['runs'][0]['name']]
    for key, record in metric_records[metrics['runs'][0]['name']].items():
        for field in ['outputBytes', 'fnv1aChecksum', 'samples', 'warmupSamples', 'repetitionsPerSample']:
            if record[field] != common[key][field]:
                raise RuntimeError(f'Metrics harness differs from common workload: {key}, {field}')
    metrics['comparisons'] = comparisons(metrics['runs'], metric_records, ['ordinary', 'metrics'])
    metrics['reviewRequired'] = [r['name'] + '/' + r['mode'] for r in metrics['comparisons'] if r['requiresReview']]
    metadata['metrics'] = metrics
    metadata['status'] = 'measured'
    (OUTPUT / 'comparison.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps({'baselineCommit': BASELINE, 'candidateCommit': candidate, 'runs': len(metadata['runs']),
                      'recordsCompared': len(metadata['comparisons']), 'reviewRequired': metadata['reviewRequired'],
                      'metricsRuns': len(metrics['runs']), 'metricsRecords': len(metrics['comparisons']),
                      'metricsReviewRequired': metrics['reviewRequired']}, indent=2))


if __name__ == '__main__':
    main()
