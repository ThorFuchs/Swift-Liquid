#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare inert SL21 inventory identities to retained historical metadata.

The selected set of the 425-exclusion snapshot is reconstructed from the older
488-exclusion matrix, its 63 separately retained admission identities, and the
historical 425-case review. No current result or outcome is inferred.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / 'Documentation/ControlTower/CONFORMANCE-DISPOSITION.json'
ADMISSIONS = ROOT / 'Tools/LiquidSpecAdapter/ExclusionCandidates.json'
FIELDS = ('sourceLocation', 'sourceDigest', 'parserMode', 'renderMode', 'featureTags')
GROUPS = {'filesystemCandidates': 'unused_filesystem_callback',
          'rangeMetadataCandidates': 'unused_resource_limits',
          'commentCandidates': 'comment_only_filesystem_callback',
          'longStringCandidates': 'materialized_long_string',
          'missingFileCandidates': 'missing_file_diagnostics'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unique(rows):
    values = {row['caseID']: row for row in rows}
    if len(values) != len(rows):
        raise ValueError('Duplicate variant identity')
    return values


def compare(inventory, earlier, holds, admissions):
    now = unique(inventory['variants'])
    old = unique(earlier)
    held = unique(holds['cases'])
    if {key for key in admissions if key.endswith('Candidates')} != set(GROUPS):
        raise ValueError('Admission policy groups differ')
    admitted_rows = [dict(entry, expectedAdmission=kind) for key, kind in GROUPS.items() for entry in admissions[key]]
    admitted = unique(admitted_rows)
    if inventory['specPin'] != admissions['specPin'] or inventory['specPin'] != holds['baseline']['specCommit']:
        raise ValueError('Reference pins differ')
    if len(now) != 5112 or set(now) != set(old):
        raise ValueError('Identity population differs')
    previously_excluded = {case for case, row in old.items() if not row['selected']}
    if len(previously_excluded) != 488 or len(held) != 425 or len(admitted) != 63 or set(held) & set(admitted) or previously_excluded != set(held) | set(admitted):
        raise ValueError('Historical exclusion partition differs')
    rows = []
    for case in sorted(now):
        current, before = now[case], old[case]
        changed = [field for field in FIELDS if current[field] != before[field]]
        if changed:
            raise ValueError('Identity metadata changed for ' + case + ': ' + ', '.join(changed))
        if case in admitted and admitted[case]['sourceDigest'] != current['sourceDigest']:
            raise ValueError('Admission digest differs: ' + case)
        if case in held and any(held[case][field] != current[field] for field in FIELDS):
            raise ValueError('Historical hold metadata differs: ' + case)
        selection = current['selection']
        expected_selected = case not in held
        if selection['selected'] != expected_selected:
            raise ValueError('Selection differs: ' + case)
        if case in held and selection['reason'] != before['reason']:
            raise ValueError('Historical exclusion reason differs: ' + case)
        expected_admission = admitted[case]['expectedAdmission'] if case in admitted else None
        if selection['admission'] != expected_admission:
            raise ValueError('Admission kind differs: ' + case)
        rows.append({'caseID': case, 'sourceDigest': current['sourceDigest'],
                     'parserMode': current['parserMode'], 'renderMode': current['renderMode'],
                     'earlierSelection': 'selected' if before['selected'] else 'unexecuted',
                     'historicalSelection': 'unexecuted' if case in held else 'selected',
                     'historicalSelectionEvidence': '425-case-review' if case in held else '63-case-admission' if case in admitted else 'earlier-selected',
                     'currentSelection': 'selected' if selection['selected'] else 'unexecuted', 'historicalOutcome': 'not-available-in-this-comparison',
                     'currentOutcome': 'not-executed', 'identityMetadata': 'matched'})
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--earlier-matrix', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Refusing to overwrite comparison')
    inventory = json.loads(args.inventory.read_text())
    earlier = json.loads(args.earlier_matrix.read_text())
    holds = json.loads(REVIEW.read_text())
    admissions = json.loads(ADMISSIONS.read_text())
    rows = compare(inventory, earlier, holds, admissions)
    result = {'schemaVersion': 1, 'status': 'IDENTITY_AND_INERT_SELECTION_ONLY',
              'limitations': 'Historical selection is reconstructed from retained evidence and compared to inert preflight. No materialized inputs or historical/current outcomes were compared.',
              'inputs': {'inventorySHA256': digest(args.inventory), 'earlierMatrixSHA256': digest(args.earlier_matrix),
                         'holdRegisterSHA256': digest(REVIEW), 'admissionsSHA256': digest(ADMISSIONS)},
              'rows': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(f'Compared {len(rows)} identities and inert selections against 4,687 reconstructed historical selections and 425 holds; outcomes not evaluated.')


if __name__ == '__main__':
    main()
