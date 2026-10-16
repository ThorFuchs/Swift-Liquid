#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Audit independent receipts. Dimensions explain failures, never replace verdicts."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from liquid_spec_diagnostics import dimensions


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def indexed(rows):
    result = {r['caseID']: r for r in rows}
    if len(result) != len(rows):
        raise ValueError('Duplicate caseID')
    identities = {(r['suite'], r['sourceLocation']['file'], r['sourceLocation']['line'],
                   r['case'], r['parserMode'], r['renderMode']) for r in rows}
    if len(identities) != len(rows):
        raise ValueError('Duplicate source/mode identity')
    return result


def eligibility(row):
    return {k: row[k] for k in ['selected', 'reason', 'featureTags', 'parserMode', 'renderMode',
                               'sourceLocation', 'sourceDigest', 'expectation']}


def audit(rows, original=None):
    current = indexed(rows)
    if original is not None:
        prior = indexed(original)
        if current.keys() != prior.keys() or any(eligibility(r) != eligibility(prior[k]) for k, r in current.items()):
            raise ValueError('Eligibility, fixture bytes, or identities changed')
    for r in rows:
        if r['selected']:
            v = r['upstreamVerdict']
            if r['comparison'] != ('matched' if v['passed'] else 'mismatched'):
                raise ValueError('Raw upstream verdict was overridden')
            if r['qualificationComparison'] == 'matched' and not v['passed']:
                raise ValueError('Supplemental policy created a pass')
            if not r['sourceDigest'] or not r['resultDigest']:
                raise ValueError('Missing source/result evidence')
    ledger = [{'caseID': r['caseID'], 'selected': r['selected'], 'sourceLocation': r['sourceLocation'],
               'sourceDigest': r['sourceDigest'], 'resultDigest': r['resultDigest'],
               'semanticResultDigest': r.get('semanticResultDigest'),
               'upstreamVerdict': r.get('upstreamVerdict'), 'qualificationComparison': r['qualificationComparison'],
               'dimensions': dimensions(r)} for r in rows]
    selected = [r for r in rows if r['selected']]
    summary = {'variants': len(rows), 'selected': len(selected), 'disabled': len(rows)-len(selected),
               'upstreamComparisons': dict(Counter(r['comparison'] for r in selected)),
               'qualificationComparisons': dict(Counter(r['qualificationComparison'] for r in selected)),
               'rawPassWithQualificationFailure': sum(r['comparison'] == 'matched' and r['qualificationComparison'] != 'matched' for r in selected),
               'referenceQualificationConcerns': [r['caseID'] for r in selected if r['referenceQualificationComparison'] != 'matched'],
               'excluded': dict(Counter(r['observedCategory'] for r in rows if not r['selected'])),
               'portableRubyTypes': {'selected': sum('ruby_types' in r['featureTags'] for r in selected),
                                    'qualificationComparisons': dict(Counter(r['qualificationComparison'] for r in selected if 'ruby_types' in r['featureTags']))},
               'parserPhases': dict(Counter(r['observedCategory'] for r in selected if r['suite'] == 'parser_errors'))}
    if original is not None:
        original_diagnostics = {r['caseID'] for r in original if r['suite'] == 'parser_errors' and
                                r['comparison'] == 'mismatched' and r['observedCategory'] == 'parse-error'}
        summary['originalParserDiagnosticPopulation'] = len(original_diagnostics)
        summary['originalDiagnosticPartition'] = dict(Counter(r['dimensions']['diagnosticClassification'] for r in ledger if r['caseID'] in original_diagnostics))
        summary['originalPhaseDifferencePopulation'] = sum(r['suite'] == 'parser_errors' and r['observedCategory'] != 'parse-error' for r in original)
    return {'schemaVersion': 1, 'policy': 'Raw upstream verdict retained; qualification may additionally fail phase/operation. Dimensions are explanatory only.',
            'summary': summary, 'rows': ledger}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('reports', type=Path)
    p.add_argument('--original', type=Path)
    p.add_argument('--before', type=Path)
    args = p.parse_args()
    matrix = args.reports / 'ELIGIBILITY_MATRIX.json'
    rows = json.loads(matrix.read_text())
    original = json.loads(args.original.read_text()) if args.original else None
    value = audit(rows, original)
    value['matrixSHA256'] = digest(matrix)
    value['originalMatrixSHA256'] = digest(args.original) if args.original else None
    if args.before:
        before = indexed(json.loads(args.before.read_text()))
        if set(before) != {r['caseID'] for r in rows} or any(eligibility(r) != eligibility(before[r['caseID']]) for r in rows):
            raise ValueError('Before/after eligibility differs')
        changes = []
        for r in rows:
            b = before[r['caseID']]
            if not r['selected']:
                continue
            observed = ['comparison', 'qualificationComparison', 'observedCategory', 'semanticResultDigest']
            if any(r.get(k) != b.get(k) for k in observed):
                changes.append({'caseID': r['caseID'], 'sourceDigest': r['sourceDigest'],
                                'before': {k: b.get(k) for k in observed}, 'after': {k: r.get(k) for k in observed},
                                'beforeResultDigest': b['resultDigest'], 'afterResultDigest': r['resultDigest']})
        value['beforeMatrixSHA256'] = digest(args.before)
        value['transitions'] = changes
        value['transitionCounts'] = dict(Counter(b['before']['qualificationComparison'] + ' -> ' + b['after']['qualificationComparison'] for b in changes))
    target = args.reports / 'PHASE_AND_DIAGNOSTIC_LEDGER.json'
    target.write_text(json.dumps(value, indent=2, ensure_ascii=True) + '\n')
    print(json.dumps(value['summary'], sort_keys=True))


if __name__ == '__main__':
    main()
