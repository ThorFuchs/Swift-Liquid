#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate proposed dispositions without changing raw reference outcomes."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def unique(rows):
    index = {(row['mode'], row['name']): row for row in rows}
    if len(index) != len(rows):
        raise ValueError('duplicate mode/name identity')
    return index

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--predecessor-differential', type=Path, required=True)
    parser.add_argument('--original-wip-log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('refusing to overwrite evidence')
    matrix = ROOT / 'Tests/LiquidTests/Fixtures/LaxQuoteRecoveryCases.json'
    original = ROOT / 'Tests/LiquidTests/Fixtures/QuotedStringReferenceCases.json'
    register = ROOT / 'Documentation/ControlTower/SL21-02A3-DISPOSITIONS.json'
    proposed = json.loads(register.read_bytes())
    earlier = json.loads(args.predecessor_differential.read_bytes())
    matrix_rows = unique(json.loads(matrix.read_bytes())['cases'])
    earlier_rows = unique(earlier['rows'])
    if len(matrix_rows) != 75 or set(matrix_rows) != set(earlier_rows):
        raise ValueError('expanded identity population differs')
    if proposed['referenceMatrixSHA256'] != digest(matrix) or proposed['predecessorDifferentialSHA256'] != digest(args.predecessor_differential):
        raise ValueError('predecessor evidence digest differs')
    raw_differences = {key for key, row in earlier_rows.items() if not row['matchesPhaseAndBytes']}
    dispositions = unique(proposed['rows'])
    if len(raw_differences) != 21 or set(dispositions) != raw_differences:
        raise ValueError('dispositions do not account for exactly the raw differences')
    for key, row in dispositions.items():
        previous, reference = earlier_rows[key], matrix_rows[key]
        if row['sourceBytes'] != reference['sourceBytes'] or row['reference'] != previous['reference'] or row['swift'] != previous['swift']:
            raise ValueError('raw reference or Swift observation changed: ' + str(key))
        if row['classification'] not in proposed['classifications'] or not row['reason']:
            raise ValueError('invalid classification: ' + str(key))
    originals = unique(json.loads(original.read_bytes())['cases'])
    observed = {}
    for line in args.original_wip_log.read_text().splitlines():
        match = re.match(r'QUOTED-STRING (\S+) (\S+) (.*)', line)
        if match:
            key = (match[1], match[2])
            if key in observed: raise ValueError('duplicate original WIP observation')
            observed[key] = match[3]
    if len(originals) != 96 or set(originals) != set(observed):
        raise ValueError('original 96 identities differ')
    original_rows = []
    for key, row in sorted(originals.items()):
        actual = observed[key]
        if actual.startswith('output='):
            output = ast.literal_eval(actual[7:]); matches = row['outcome'] == 'output' and output == row.get('outputBytes')
        elif actual.startswith('parse-error'):
            matches = row['outcome'] == 'parse-error'
        else:
            raise ValueError('unknown original observation: ' + actual)
        original_rows.append({'mode': key[0], 'name': key[1], 'sourceBytes': row['sourceBytes'],
                              'referenceOutcome': row['outcome'], 'referenceOutputBytes': row.get('outputBytes'),
                              'swiftObservation': actual, 'matchesPhaseAndBytes': matches})
    counts = {label: sum(row['classification'] == label for row in dispositions.values()) for label in proposed['classifications']}
    report = {'status': 'ACCOUNTED_NOT_QUALIFIED', 'originalCount': len(original_rows),
              'originalMatches': sum(row['matchesPhaseAndBytes'] for row in original_rows),
              'originalDifferences': sum(not row['matchesPhaseAndBytes'] for row in original_rows),
              'expandedCount': len(earlier_rows), 'expandedMatches': len(earlier_rows) - len(raw_differences),
              'expandedDifferences': len(raw_differences), 'classifications': counts,
              'referenceFixtureSHA256': digest(original), 'rawExpandedFixtureSHA256': digest(matrix),
              'originalRows': original_rows, 'dispositionRows': list(dispositions.values())}
    with args.output.open('x') as stream:
        json.dump(report, stream, indent=2); stream.write('\n')
    print(json.dumps({key: value for key, value in report.items() if key not in ('originalRows', 'dispositionRows')}, indent=2))

if __name__ == '__main__':
    main()
