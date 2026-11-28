#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify the two deferred generated expectations against retained evidence."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'Tools/LiquidSpecAdapter/ExcludedGeneratorEvidence.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--matrix', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    args = parser.parse_args()
    evidence = json.loads(EVIDENCE.read_text())
    receipt = json.loads(args.receipt.read_text())
    if (sha(args.matrix) != evidence['historicalMatrixSHA256'] or sha(args.receipt) != evidence['historicalReceiptSHA256']
            or not receipt['sourceQualified'] or not receipt['sourceUnchanged']
            or receipt['sourceRevision']['commit'] != evidence['historicalSourceCommit']
            or receipt['pins']['spec'] != evidence['specPin']
            or receipt['reportSHA256']['ELIGIBILITY_MATRIX.json'] != sha(args.matrix)):
        raise ValueError('Historical generator receipt or matrix changed')
    rows = json.loads(args.matrix.read_text())
    indexed = {row['caseID']: row for row in rows}
    if len(indexed) != len(rows) or len(evidence['cases']) != 2 or evidence['seed'] != 15401:
        raise ValueError('Historical generator evidence population changed')
    for item in evidence['cases']:
        row = indexed[item['caseID']]
        if (row['selected'] or row['comparison'] != 'not-executed' or row['sourceDigest'] != item['sourceDigest']
                or row['expectation'] != {'output': item['historicalSeededOutput'], 'outputPattern': None, 'errors': {}}):
            raise ValueError('Historical generator evidence changed: ' + item['caseID'])
    print('Verified two excluded historical seeded metadata values; no generator or comparator executed.')


if __name__ == '__main__':
    main()
