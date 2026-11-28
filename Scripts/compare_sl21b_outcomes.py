#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare exact-source SL21-01B results with the qualified SL21-01A2 matrix."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from ci import ROOT, source_revision


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_receipt(path, current=False):
    receipt = json.loads(path.read_text())
    matrix = path.parent / 'spec/ELIGIBILITY_MATRIX.json'
    if (not receipt['sourceQualified'] or not receipt['sourceUnchanged'] or
            receipt['reportSHA256']['ELIGIBILITY_MATRIX.json'] != sha(matrix) or
            receipt['pins'] != {'spec': '84bf25e0edbca5f7e530574788b0f875ab331f50',
                                'ruby': '4e39ae4cc3da73921923c0669e0fc84a66b2f696'}):
        raise ValueError('Receipt or matrix binding invalid')
    if current and (receipt['sourceRevision'] != source_revision() or receipt['endingSourceRevision'] != source_revision()):
        raise ValueError('Candidate receipt is not bound to clean current source')
    rows = json.loads(matrix.read_text())
    index = {row['caseID']: row for row in rows}
    if len(rows) != 5112 or len(index) != 5112:
        raise ValueError('Identity population changed')
    return receipt, index, matrix


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline-receipt', type=Path, required=True)
    parser.add_argument('--candidate-receipt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Refusing to overwrite evidence')
    before_receipt, before, before_path = load_receipt(args.baseline_receipt)
    after_receipt, after, after_path = load_receipt(args.candidate_receipt, current=True)
    if before_receipt['sourceRevision'] != {'commit': 'd02485da8a90daf83b3b3293c35ab09c2e11ccb5',
                                           'tree': '2d812a3db592e632dee62042aded959e0e76e88b', 'clean': True}:
        raise ValueError('Baseline source changed')
    if set(before) != set(after):
        raise ValueError('Identity sets differ')
    study = json.loads((ROOT / 'Documentation/LQ1/STANDARD-DROPS-2.1.json').read_text())
    candidates = {row['caseID'] for row in study['cases']}
    if len(candidates) != 56:
        raise ValueError('Candidate identity population differs')
    identity_fields = ('sourceLocation', 'sourceDigest', 'parserMode', 'renderMode', 'featureTags')
    observation_fields = ('comparison', 'qualificationComparison', 'observedCategory', 'actual', 'renderedOutput',
                          'semanticResultDigest', 'reportedErrors', 'referenceComparison', 'referenceQualificationComparison',
                          'referenceObservedCategory', 'referenceActual', 'referenceReportedErrors',
                          'upstreamVerdict', 'referenceUpstreamVerdict')
    rows, transitions, differences = [], Counter(), Counter()
    for case in sorted(before):
        old, new = before[case], after[case]
        if any(old[key] != new[key] for key in identity_fields):
            raise ValueError('Identity metadata changed: ' + case)
        if new['selected'] != (old['selected'] or case in candidates) or (case in candidates and old['selected']):
            raise ValueError('Selection drift: ' + case)
        if case in candidates and new.get('admission') != 'guarded_standard_drop':
            raise ValueError('Candidate admission policy missing: ' + case)
        changes = {field: {'before': old.get(field), 'after': new.get(field)} for field in observation_fields
                   if old.get(field) != new.get(field)}
        if old['selected']:
            differences.update(changes)
        transition = old['qualificationComparison'] + ' -> ' + new['qualificationComparison']
        transitions[transition] += 1
        rows.append({'caseID': case, **{key: new[key] for key in identity_fields},
                     'baselineSelected': old['selected'], 'candidateSelected': new['selected'],
                     'admission': new.get('admission'), 'swiftTransition': transition,
                     'rubyTransition': (old.get('referenceQualificationComparison') or 'not-executed') + ' -> ' +
                                       (new.get('referenceQualificationComparison') or 'not-executed'),
                     'baseline': {field: old.get(field) for field in observation_fields},
                     'candidate': {field: new.get(field) for field in observation_fields},
                     'observationChanges': changes})
    result = {'schemaVersion': 1, 'status': 'COMPLETE_IDENTITY_COMPARISON',
              'baselineReceiptSHA256': sha(args.baseline_receipt), 'baselineMatrixSHA256': sha(before_path),
              'candidateReceiptSHA256': sha(args.candidate_receipt), 'candidateMatrixSHA256': sha(after_path),
              'baselineSource': before_receipt['sourceRevision'], 'candidateSource': after_receipt['sourceRevision'],
              'summary': {'swiftTransitions': dict(transitions), 'previouslySelectedObservationDifferences': dict(differences),
                          'rubyTransitions': dict(Counter(row['rubyTransition'] for row in rows))}, 'rows': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False)
        stream.write('\n')
    print(json.dumps(result['summary'], sort_keys=True))
    if differences:
        raise ValueError('Previously selected observations changed; see retained comparison')


if __name__ == '__main__':
    main()
