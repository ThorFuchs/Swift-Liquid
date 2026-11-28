#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the provisional SL21-01 hold register against historical evidence.

Optional --spec-path verifies pinned fixture bytes and clean checkout. This is
an inventory validation, not a conformance test or a complete semantic review.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REGISTER = ROOT / 'Documentation/ControlTower/CONFORMANCE-DISPOSITION.json'
REVIEW = ROOT / 'Documentation/LQ1/UNEXECUTED-CASE-REVIEW.md'
STUDY = ROOT / 'Documentation/LQ1/STANDARD-DROPS-2.1.json'
POLICIES = ROOT / 'Tools/LiquidSpecAdapter'
SPEC_PIN = '84bf25e0edbca5f7e530574788b0f875ab331f50'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--spec-path', type=Path)
    parser.add_argument('--targeted-root', type=Path, help='Optional external targeted-lane receipt directory')
    args = parser.parse_args()
    data = json.loads(REGISTER.read_text())
    require(data['schemaVersion'] == 1 and data['status'] == 'PROVISIONAL_HOLD_NOT_SCOPE_ACCEPTANCE', 'Register status changed')
    require(data['baseline']['specCommit'] == SPEC_PIN, 'Spec pin changed')
    require(data['baseline']['historicalReviewSHA256'] == hashlib.sha256(REVIEW.read_bytes()).hexdigest(), 'Historical review changed')
    historical = {}
    for line in REVIEW.read_text().splitlines():
        if not line.startswith('| ['):
            continue
        match = re.fullmatch(r'\| \[(.*)\]\((https://[^)]*)\) \| (.*) \|', line)
        require(match is not None, 'Unparseable historical row')
        case, url, reason = match.groups()
        require(case not in historical, 'Duplicate historical identity: ' + case)
        historical[case] = (url, reason)
    cases = data['cases']
    by_id = {row['caseID']: row for row in cases}
    require(len(historical) == len(cases) == len(by_id) == 425 and set(by_id) == set(historical), 'Historical population differs')
    for case, row in by_id.items():
        require((row['historicalSource'], row['historicalReason']) == historical[case], 'Historical evidence changed: ' + case)
        require(row['disposition'] == 'hold_unexecuted' and row['qualification'] == 'not-executed-in-full-suite', 'Unexpected admission: ' + case)
        require(row['categories'] and re.fullmatch(r'[0-9a-f]{64}', row['sourceDigest']) is not None, 'Invalid classification or digest: ' + case)
        require(case.endswith('/' + row['parserMode'] + '/' + row['renderMode']), 'Mode identity differs: ' + case)
    study = json.loads(STUDY.read_text())['cases']
    mapped = {}
    for path in sorted(POLICIES.glob('*Drop*Cases.json')):
        policy = json.loads(path.read_text())
        require(policy['specPin'] == SPEC_PIN, 'Policy pin changed: ' + str(path))
        for item in policy['cases'] + policy.get('generatedCases', []):
            if 'caseID' in item:
                candidates = [c for c in study if c['caseID'] == item['caseID'] and c['sourceDigest'] == item['sourceDigest']]
                if candidates:
                    c = candidates[0]
                    require(all(c[k] == item[k] for k in ('sourceLocation', 'parserMode', 'renderMode', 'featureTags')), 'Policy metadata differs: ' + item['caseID'])
            else:
                candidates = [c for c in study if c['fixture']['name'] == item['name'] and c['sourceLocation']['line'] == item['line'] and c['sourceLocation']['file'] == policy['fixture'] and c['sourceDigest'] == policy['fixtureSHA256']]
            require(len(candidates) == 1, 'Ambiguous policy identity in ' + str(path))
            candidate = candidates[0]
            case = candidate['caseID']
            require(case not in mapped and case in by_id, 'Duplicate or missing targeted case: ' + case)
            row = by_id[case]
            require(row['targetedPolicy'] == path.stem and row['sourceDigest'] == candidate['sourceDigest'] and row['sourceLocation'] == candidate['sourceLocation'] and row['parserMode'] == candidate['parserMode'] and row['renderMode'] == candidate['renderMode'] and row['featureTags'] == candidate['featureTags'], 'Study/register mismatch: ' + case)
            mapped[case] = path.stem
    require(len(study) == len(mapped) == 56 and {r['caseID'] for r in cases if r['targetedPolicy']} == set(mapped), 'Targeted population differs')
    comparison = json.loads((REGISTER.parent / 'IDENTITY-COMPARISON.json').read_text())
    compared = {row['caseID']: row for row in comparison['rows']}
    require(comparison['status'] == 'PARTIAL_COMPARISON' and len(comparison['rows']) == len(compared) == 425 and set(compared) == set(by_id), 'Partial comparison population differs')
    for case, row in compared.items():
        original = by_id[case]
        require(all(row[k] == original[k] for k in ('sourceDigest', 'parserMode', 'renderMode')), 'Comparison identity differs: ' + case)
        require(row['historicalFullSuite'] == 'not-executed' and row['currentFullSuite'] == 'not-run', 'Unproven full-suite result: ' + case)
        require((row['targetedEvidence'] is not None) == (case in mapped), 'Targeted comparison differs: ' + case)
    if args.targeted_root:
        observed = set()
        for receipt_path in sorted(args.targeted_root.glob('*/receipt.json')):
            receipt = json.loads(receipt_path.read_text())
            report_path = receipt_path.parent / 'cases.json'
            report = json.loads(report_path.read_text())
            digest = hashlib.sha256(report_path.read_bytes()).hexdigest()
            require(receipt['status'] == 'passed' and receipt['sourceQualified'] and report['status'] == 'passed' and digest == receipt['caseReportSHA256'], 'Invalid targeted receipt: ' + str(receipt_path))
            for result in report['cases']:
                case = result['caseID']
                require(case in mapped and case not in observed, 'Unexpected targeted result: ' + case)
                observed.add(case)
                evidence = compared[case]['targetedEvidence']
                samples = result.get('samples', [result])
                require(all(s['swift']['passed'] and s['reference']['passed'] for s in samples), 'Nonmatching targeted result: ' + case)
                require(evidence['lane'] == receipt['lane'] and evidence['reportSHA256'] == digest and evidence['materializations'] == len(samples) and evidence['outcome'] == result.get('outcome', 'matched-fixture-expectation') and evidence['swiftComparator'] == evidence['rubyComparator'] == 'matched', 'Targeted comparison evidence differs: ' + case)
        require(observed == set(mapped), 'Targeted receipt population differs')
    if args.spec_path:
        spec = args.spec_path.resolve()
        def git(*command):
            return subprocess.check_output(['git', '-C', str(spec), *command], text=True).strip()
        require(git('rev-parse', 'HEAD') == SPEC_PIN and not git('status', '--porcelain'), 'Spec checkout is not clean and pinned')
        for row in cases:
            path = (spec / row['sourceLocation']['file']).resolve()
            require(path.is_relative_to(spec) and path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == row['sourceDigest'], 'Fixture digest mismatch: ' + row['caseID'])
    print('Validated 425 held identities and 56 distinct targeted mappings' + (' and pinned fixture bytes' if args.spec_path else '') + (' and targeted receipts' if args.targeted_root else '') + '; no full-suite verdict inferred.')


if __name__ == '__main__':
    main()
