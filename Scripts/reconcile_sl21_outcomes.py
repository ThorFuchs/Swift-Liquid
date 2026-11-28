#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Report all variant outcomes without inventing the missing 425-hold raw matrix."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from ci import ROOT, source_revision


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_receipt(path, clean_current=False):
    receipt = json.loads(path.read_text())
    matrix = path.parent / 'spec/ELIGIBILITY_MATRIX.json'
    if (not receipt['sourceQualified'] or not receipt['sourceUnchanged']
            or receipt['reportSHA256']['ELIGIBILITY_MATRIX.json'] != sha(matrix)
            or receipt['pins'] != {'spec': '84bf25e0edbca5f7e530574788b0f875ab331f50',
                                   'ruby': '4e39ae4cc3da73921923c0669e0fc84a66b2f696'}):
        raise ValueError('Receipt or matrix binding invalid')
    if clean_current and (receipt['sourceRevision'] != source_revision() or receipt['endingSourceRevision'] != source_revision()):
        raise ValueError('Fresh receipt is not bound to the current clean source')
    rows = json.loads(matrix.read_text())
    result = {row['caseID']: row for row in rows}
    if len(rows) != len(result) or len(rows) != 5112:
        raise ValueError('Matrix identity population differs')
    return receipt, result, matrix


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--earlier-receipt', type=Path, required=True)
    parser.add_argument('--current-receipt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Refusing to overwrite comparison')
    old_receipt, before, old_path = load_receipt(args.earlier_receipt)
    new_receipt, after, new_path = load_receipt(args.current_receipt, clean_current=True)
    if set(before) != set(after):
        raise ValueError('Before/after identities differ')
    holds = {x['caseID'] for x in json.loads((ROOT / 'Documentation/ControlTower/CONFORMANCE-DISPOSITION.json').read_text())['cases']}
    conflicts = {x['caseID'] for x in json.loads((ROOT / 'Tools/LiquidSpecAdapter/ReviewedConflicts.json').read_text())['conflicts']}
    fields = ('sourceLocation', 'sourceDigest', 'parserMode', 'renderMode', 'featureTags')
    rows = []
    for case in sorted(after):
        old, new = before[case], after[case]
        if any(old[key] != new[key] for key in fields) or new['selected'] == (case in holds):
            raise ValueError('Identity or historical selection changed: ' + case)
        if case in holds:
            historical = 'excluded-in-425-hold-review'
        elif case in conflicts:
            historical = 'identified-reference-conflict-in-reviewed-policy'
        else:
            historical = 'selected-outcome-not-individually-available-for-425-hold-run'
        row = {'caseID': case, 'sourceDigest': new['sourceDigest'], 'parserMode': new['parserMode'],
               'renderMode': new['renderMode'], 'historical425HoldEvidence': historical,
               'earlier488Hold': {'selected': old['selected'], 'comparison': old['comparison'],
                                  'qualificationComparison': old['qualificationComparison'], 'observedCategory': old['observedCategory']},
               'fresh': {key: new.get(key) for key in ('selected', 'comparison', 'qualificationComparison', 'observedCategory',
                   'referenceComparison', 'referenceQualificationComparison', 'referenceObservedCategory', 'upstreamVerdict', 'referenceUpstreamVerdict')}}
        rows.append(row)
    summaries = {'freshSwift': dict(Counter(row['fresh']['qualificationComparison'] for row in rows)),
                 'freshRuby': dict(Counter(row['fresh']['referenceQualificationComparison'] or 'not-executed' for row in rows)),
                 'historical425HoldEvidence': dict(Counter(row['historical425HoldEvidence'] for row in rows))}
    result = {'schemaVersion': 1, 'status': 'FRESH_OUTCOMES_WITH_PARTIAL_HISTORICAL_COMPARISON',
              'limitations': 'The 425-hold run raw matrix was not found; its selected case outcomes cannot be individually compared. Earlier 488-hold outcomes are from a different source commit. No missing outcome is inferred.',
              'sources': {'earlierReceiptSHA256': sha(args.earlier_receipt), 'earlierMatrixSHA256': sha(old_path),
                          'earlierRevision': old_receipt['sourceRevision'], 'currentReceiptSHA256': sha(args.current_receipt),
                          'currentMatrixSHA256': sha(new_path), 'currentRevision': new_receipt['sourceRevision']},
              'summary': summaries, 'rows': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps(summaries, sort_keys=True))


if __name__ == '__main__':
    main()
