#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Produce an observed disposition overlay without rewriting the historical register."""
import argparse
import hashlib
import json
from pathlib import Path
from ci import ROOT, source_revision


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Refusing to overwrite disposition evidence')
    receipt = json.loads(args.receipt.read_text())
    matrix_path = args.receipt.parent / 'spec/ELIGIBILITY_MATRIX.json'
    revision = source_revision()
    if (not revision.get('clean') or receipt['sourceRevision'] != revision or receipt['endingSourceRevision'] != revision or
            not receipt['sourceQualified'] or not receipt['sourceUnchanged'] or
            receipt['reportSHA256']['ELIGIBILITY_MATRIX.json'] != sha(matrix_path)):
        raise ValueError('Source-qualified matrix binding invalid')
    original_path = ROOT / 'Documentation/ControlTower/CONFORMANCE-DISPOSITION.json'
    original = json.loads(original_path.read_text())
    study = json.loads((ROOT / 'Documentation/LQ1/STANDARD-DROPS-2.1.json').read_text())
    candidates = {row['caseID'] for row in study['cases']}
    matrix = json.loads(matrix_path.read_text())
    index = {row['caseID']: row for row in matrix}
    if len(index) != len(matrix) or len(matrix) != 5112 or len(candidates) != 56 or len(original['cases']) != 425:
        raise ValueError('Identity population changed')
    rows = []
    for historic in original['cases']:
        case = historic['caseID']
        row = index[case]
        if case in candidates:
            if (not row['selected'] or row.get('admission') != 'guarded_standard_drop' or
                    row['qualificationComparison'] != 'matched' or row['referenceQualificationComparison'] != 'matched'):
                raise ValueError('Candidate does not satisfy admission: ' + case)
            disposition = 'admitted-qualified-match'
        else:
            if row['selected'] or row['qualificationComparison'] != 'not-executed':
                raise ValueError('Historical exclusion changed: ' + case)
            disposition = 'hold-unexecuted'
        rows.append({'caseID': case, 'sourceDigest': row['sourceDigest'], 'parserMode': row['parserMode'],
                     'renderMode': row['renderMode'], 'historicalDisposition': historic['disposition'],
                     'disposition': disposition, 'swiftQualification': row['qualificationComparison'],
                     'rubyQualification': row.get('referenceQualificationComparison')})
    if len({row['caseID'] for row in rows}) != 425:
        raise ValueError('Duplicate disposition identity')
    result = {'schemaVersion': 1, 'status': 'OBSERVED_SOURCE_BOUND_OVERLAY', 'candidateSource': revision,
              'originalRegisterSHA256': sha(original_path), 'receiptSHA256': sha(args.receipt),
              'matrixSHA256': sha(matrix_path), 'admitted': 56, 'held': 369, 'cases': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False)
        stream.write('\n')
    print('Recorded 56 qualified admissions and 369 historical holds without modifying the original register')


if __name__ == '__main__':
    main()
