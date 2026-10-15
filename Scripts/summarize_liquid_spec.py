#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Summarize immutable liquid-spec receipts without changing comparison outcomes."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def key(row):
    return (row['suite'], row['case'], row['parserMode'], row['renderMode'], row['sourceLocation']['file'], str(row['sourceLocation']['line']))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('reports', type=Path)
    parser.add_argument('--initial', type=Path)
    args = parser.parse_args()
    matrix_path = args.reports / 'ELIGIBILITY_MATRIX.json'
    rows = json.loads(matrix_path.read_text())
    runs = json.loads((args.reports / 'SPEC_RUNS.json').read_text())
    assert len(rows) == runs['observedRows'] == sum(s['expandedVariants'] for s in runs['suites'])
    assert len({key(row) for row in rows}) == len(rows), 'Duplicate case/mode identities'
    selected = [row for row in rows if row['selected']]
    failures = [row for row in selected if row['comparison'] != 'matched']
    assert all(row['resultDigest'] and row['sourceLocation']['file'] for row in rows)
    counts = Counter(row['comparison'] for row in selected)
    lines = ['# Independent liquid-spec mismatch receipts', '',
             'Generated from the unchanged raw matrix. A comparator match may be exact output or required error/output patterns.',
             'Parser/render phase is also checked. No exclusions, operational errors or reference failures are counted as renders.', '',
             f'Matrix SHA-256: `{hashlib.sha256(matrix_path.read_bytes()).hexdigest()}`.', '',
             f'{len(rows)} rows; {len(selected)} selected; {dict(counts)}; {len(rows)-len(selected)} not executed.', '',
             '| Suite | Source cases | Variants | Selected | Matched | Mismatched | Operational | Disabled |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for suite in runs['suites']:
        c = suite['comparisons']
        lines.append(f"| {suite['suite']} | {suite['loadedSourceCases']} | {suite['expandedVariants']} | {suite['selected']} | {c.get('matched', 0)} | {c.get('mismatched', 0)} | {c.get('operational-error', 0)} | {suite['disabledCases']} |")
    lines += ['', '## Classification', '', 'Unresolved means no reviewed general-rule repair has been applied. Symptom labels do not establish root cause.', '']
    triage = []
    for row in failures:
        category = 'unresolved'
        note = 'Requires minimal reproduction, domain review and general-rule analysis before a core repair.'
        if row.get('referenceComparison') != 'matched':
            category = 'test-suite-concern'
            note = 'Pinned Ruby also differs from this expectation under the recorded runner/hosting policy; review reference policy before an engine repair.'
        elif row['observedCategory'] == 'operational-error' and (row.get('reportedErrors') or {}).get('message', '').startswith('Limit exceeded:'):
            category = 'documented-bounded-domain-divergence'
            note = 'Finite Swift quota is operational, not a recoverable Liquid error. Keep the failure; do not loosen quota policy.'
        symptom = 'output-or-runtime-rule'
        if row['expectedCategory'] == 'parse-error':
            symptom = 'parser-diagnostic-mismatch' if row['observedCategory'] == 'parse-error' else 'parser-acceptance-or-error-phase'
        elif row['observedCategory'] == 'parse-error':
            symptom = 'unexpected-parse-rejection'
        triage.append({'suite': row['suite'], 'case': row['case'], 'parserMode': row['parserMode'],
                       'renderMode': row['renderMode'], 'sourceLocation': row['sourceLocation'],
                       'resultDigest': row['resultDigest'], 'category': category, 'symptom': symptom, 'reason': note})
    lines += [f'- {category}: {count}' for category, count in sorted(Counter(r['category'] for r in triage).items())]
    lines += ['', '## Exact selected failures', '', '| Suite / case | Parser / render | Source | Expected → observed category | Comparison / triage | Result SHA-256 |', '| --- | --- | --- | --- | --- | --- |']
    for row, finding in zip(failures, triage):
        name = row['case'].replace('|', '\\|').replace('\n', ' ')
        location = row['sourceLocation']
        url = 'https://github.com/Shopify/liquid-spec/blob/84bf25e0edbca5f7e530574788b0f875ab331f50/' + location['file'] + '#L' + str(location['line'])
        lines.append(f"| {row['suite']} / {name} | {row['parserMode']} / {row['renderMode']} | [{location['file']}:{location['line']}]({url}) | {row['expectedCategory']} → {row['observedCategory']} | {row['comparison']} / {finding['category']} | `{row['resultDigest']}` |")
    refs = [r for r in rows if r.get('referenceComparison') == 'mismatched']
    lines += ['', '## Pinned reference expectation mismatches', '']
    lines += ['- ' + r['suite'] + ' / ' + r['case'] for r in refs]
    lines += ['', '## Exclusion accounting', '']
    lines += [f'- {reason}: {count}' for reason, count in sorted(Counter(r['reason'] for r in rows if not r['selected']).items())]
    repairs = []
    if args.initial:
        initial = {key(r): r for r in json.loads(args.initial.read_text())}
        for row in selected:
            before = initial.get(key(row))
            if before and before['comparison'] != 'matched' and row['comparison'] == 'matched':
                repairs.append({'identity': key(row), 'beforeActual': before.get('actual'), 'afterActual': row.get('actual'),
                                'beforeResultDigest': before['resultDigest'], 'afterResultDigest': row['resultDigest'],
                                'referenceComparison': row['referenceComparison'], 'sourceLocation': row['sourceLocation']})
        lines += ['', '## Changed outcomes from retained initial run', '']
        lines += ['- ' + ' / '.join(r['identity']) + ': failing comparison → matched (see CORE_REPAIR.json).' for r in repairs]
    (args.reports / 'TRIAGE.json').write_text(json.dumps(triage, indent=2) + '\n')
    (args.reports / 'CORE_REPAIR.json').write_text(json.dumps({'repairs': repairs, 'historicalFixturesChanged': False}, indent=2) + '\n')
    (args.reports / 'MISMATCHES.md').write_text('\n'.join(lines) + '\n')
    print(json.dumps({'rows': len(rows), 'selected': len(selected), 'comparisons': counts,
                      'disabled': len(rows)-len(selected), 'triage': Counter(r['category'] for r in triage),
                      'referenceMismatches': len(refs), 'changedOutcomes': len(repairs)}))


if __name__ == '__main__':
    main()
