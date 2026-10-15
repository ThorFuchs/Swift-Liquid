# SPDX-License-Identifier: Apache-2.0
"""Admit measured maintenance observations; timings carry no pass/fail deadline."""
import json
import math
import statistics
from pathlib import Path
import sys

POLICIES = ['ordinary', 'diagnostics', 'metrics', 'diagnosticsAndMetrics']
SOURCES = {
    'large-loop': "{% for item in items %}{{ item }}{% endfor %}",
    'large-escape': "{{ text | escape }}",
    'partial-fanout': "{% for item in (1..256) %}{% render 'row' %}{% endfor %}",
}
PARTIAL = '<p>Swift &amp; Liquid</p>'
OUTPUTS = {'large-loop': 'Swift-🌊;' * 1024, 'large-escape': '&lt;Swift &amp; Liquid&gt;' * 8192,
           'partial-fanout': PARTIAL * 256}
UNITS = {'large-loop': 1024, 'large-escape': len(('<Swift & Liquid>' * 8192).encode()), 'partial-fanout': 256}


def checksum(text):
    value = 14695981039346656037
    for byte in text.encode(): value = ((value ^ byte) * 1099511628211) & ((1 << 64) - 1)
    return format(value, 'x')


def samples(values, count=25):
    if not isinstance(values, list) or len(values) != count or any(
            type(value) not in [int, float] or not math.isfinite(value) or value <= 0 for value in values):
        raise RuntimeError('Missing or invalid maintenance observations')
    return sorted(values)


def summary(record, field):
    ordered = samples(record.get(field))
    for key, expected in [('medianNanoseconds', ordered[12]), ('p95Nanoseconds', ordered[23]),
                          ('minimumNanoseconds', ordered[0]), ('maximumNanoseconds', ordered[24])]:
        if record.get(key) != expected: raise RuntimeError('Maintenance summary differs from raw observations')
    if record.get('samples') != 25 or record.get('warmupSamples') != 5:
        raise RuntimeError('Maintenance sampling policy changed')


def validate(result):
    if result.get('schemaVersion') != 1 or result.get('configuration') != 'release' or result.get('operation') != 'measured-maintenance':
        raise RuntimeError('Missing maintenance measurement identity')
    if result.get('schedulerConfiguration') != 'concurrent driver, detached workers, Dispatch cancellation controller':
        raise RuntimeError('Unreviewed cancellation executor placement')
    large = result.get('largeWorkloads', [])
    expected = {(name, mode) for name in OUTPUTS for mode in ['source', 'parsed']}
    if len(large) != 6 or {(r['workload'], r['mode']) for r in large} != expected:
        raise RuntimeError('Incomplete or duplicate larger workload modes')
    for record in large:
        name = record['workload']; output = OUTPUTS[name]
        source_bytes = len(SOURCES[name].encode()) + (len(PARTIAL.encode()) if name == 'partial-fanout' else 0)
        if (record['outputBytes'], record['checksumFNV1a64'], record['units'], record['sourceBytes'], record['repetitions']) != (
                len(output.encode()), checksum(output), UNITS[name], source_bytes, 1):
            raise RuntimeError('Larger workload output or shape differs')
        summary(record, 'nanosecondsPerOperation')
    cancellation = result.get('cancellation', [])
    expected = {(policy, mode, host) for policy in POLICIES for mode in ['source', 'parsed']
                for host in ['cooperative', 'explicit-release']}
    if len(cancellation) != 16 or {(r['policy'], r['mode'], r['host']) for r in cancellation} != expected:
        raise RuntimeError('Incomplete or duplicate cancellation scenarios')
    for record in cancellation:
        summary(record, 'cancelToCompletionNanoseconds')
        if record['cancelledSamples'] != 25 or record['continuedSamples'] != 0 or record['healthyReuse'] is not True:
            raise RuntimeError('Cancellation lost its identity, continued, or damaged reuse')
        delays, responses = record['cancelToReleaseNanoseconds'], record['releaseToCompletionNanoseconds']
        if record['host'] == 'cooperative':
            if delays != [] or responses != []: raise RuntimeError('Cooperative host has no explicit-release boundary')
        else:
            samples(delays); samples(responses)
            for total, delay, response in zip(record['cancelToCompletionNanoseconds'], delays, responses):
                if abs(total - delay - response) > 1.0:
                    raise RuntimeError('Cancellation intervals do not share the same boundaries')
    runnable = result.get('runnableCancellation', [])
    expected = {(policy, mode) for policy in POLICIES for mode in ['source', 'parsed']}
    if len(runnable) != 8 or {(r['policy'], r['mode']) for r in runnable} != expected:
        raise RuntimeError('Incomplete or duplicate runnable cancellation scenarios')
    for record in runnable:
        if (record['workload'], record['samples'], record['warmupSamples'], record['inputBytes'],
                record['expectedOutputBytes'], record['checksumFNV1a64'], record['healthyReuse']) != (
                'runnable-escape', 25, 5, UNITS['large-escape'], len(OUTPUTS['large-escape'].encode()),
                checksum(OUTPUTS['large-escape']), True):
            raise RuntimeError('Runnable shape, output or reuse differs')
        if record['healthyReuse'] is not True: raise RuntimeError('Runnable engine reuse failed')
        observations = record['observations']
        if len(observations) != 25: raise RuntimeError('Missing runnable cancellation observations')
        cancelled = []
        for observation in observations:
            interval = observation['completionRelativeToRequestNanoseconds']
            outcome = observation['outcome']
            if type(interval) not in [int, float] or not math.isfinite(interval):
                raise RuntimeError('Invalid runnable clock observation')
            if outcome == 'cancelled':
                if interval < 0: raise RuntimeError('Cancellation predates its request')
                cancelled.append(interval)
            elif outcome == 'completed-before-request':
                if interval >= 0: raise RuntimeError('Misclassified completed observation')
            elif outcome == 'completed-racing-request':
                if interval < 0: raise RuntimeError('Misclassified racing observation')
            else: raise RuntimeError('Unexpected runnable outcome')
        cancelled.sort()
        median = statistics.median(cancelled) if cancelled else None
        p95 = cancelled[math.ceil(len(cancelled) * 0.95) - 1] if cancelled else None
        if (record['cancelledSamples'], record['completedSamples'], record['cancelledMedianNanoseconds'],
                record['cancelledP95Nanoseconds']) != (len(cancelled), 25 - len(cancelled), median, p95):
            raise RuntimeError('Runnable accounting or conditional summary differs')
    return {'status': 'admitted' , 'largeRecords': len(large), 'cancellationRecords': len(cancellation), 'runnableRecords': len(runnable),
            'latencyDeadline': None, 'processMemoryClaim': False}


if __name__ == '__main__':
    print(json.dumps(validate(json.loads(Path(sys.argv[1]).read_text())), indent=2))
