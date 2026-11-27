#!/usr/bin/env python3
"""Reconcile the proposed standard-Drop cases without admitting any of them."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADAPTER = ROOT / 'Tools/LiquidSpecAdapter'
STUDY = ROOT / 'Documentation/LQ1/STANDARD-DROPS-2.1.json'
NAMES = {
    'BooleanDropCases': 'boolean-drop', 'NumberDropCases': 'number-drop',
    'StringDropCases': 'string-drop', 'MethodDropCases': 'method-drop',
    'IndexDropCases': 'index-drop', 'SequenceDropCases': 'sequence-drop',
    'NestedDropCases': 'nested-drop', 'NilDropCases': 'nil-drop',
    'OpaqueDropCases': 'opaque-drop', 'ErrorDropCases': 'error-drop',
    'ErrorDropInlineCases': 'error-drop-inline',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline-matrix', type=Path, required=True)
    parser.add_argument('--targeted-root', type=Path, required=True)
    parser.add_argument('--spec-path', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(not args.output.exists(), 'refusing to overwrite evidence')
    study = json.loads(STUDY.read_text())
    cases = study['cases']
    require(len(cases) == 56 and len({x['caseID'] for x in cases}) == 56, 'study population changed')
    baseline = json.loads(args.baseline_matrix.read_text())
    by_id = {x['caseID']: x for x in baseline}
    require(len(baseline) == 5112 and len(by_id) == 5112, 'baseline identity population changed')
    policies = {}
    receipts = {}
    for policy_name, lane in NAMES.items():
        policy_path = ADAPTER / (policy_name + '.json')
        policy = json.loads(policy_path.read_text())
        require(policy['specPin'] == study['liquidSpecCommit'] and policy['referencePin'] == study['rubyLiquidCommit'], 'pin drift: ' + lane)
        entries = policy['cases'] + policy.get('generatedCases', [])
        expanded = []
        for item in entries:
            if 'caseID' in item:
                expanded.append(item['caseID'])
            else:
                expanded.append('basics/' + policy['fixture'] + ':' + str(item['line']) + '/' + item['name'] + '/strict2/raise')
        require(len(expanded) == len(set(expanded)), 'duplicate policy identity: ' + lane)
        for case_id in expanded:
            require(case_id not in policies, 'overlapping policies: ' + case_id)
            policies[case_id] = (policy_name, lane, digest(policy_path))
        receipt_path = args.targeted_root / lane / 'receipt.json'
        report_path = args.targeted_root / lane / 'cases.json'
        receipt, report = json.loads(receipt_path.read_text()), json.loads(report_path.read_text())
        require(receipt['status'] == 'passed' and receipt['sourceQualified'] and receipt['sourceUnchanged'], 'unqualified targeted receipt: ' + lane)
        require(receipt['sourceRevision'] == {
            'commit': '187b177fb5922f2e19b1849d99f4f8d2bc9abe68',
            'tree': 'bb5e3d190f1da2e619d6c9b0f334612382087702', 'clean': True,
        }, 'targeted source drift: ' + lane)
        require(digest(report_path) == receipt['caseReportSHA256'] and report['status'] == 'passed', 'targeted report mismatch: ' + lane)
        report_rows = {x['caseID']: x for x in report['cases']}
        require(set(report_rows) == set(expanded), 'targeted identity drift: ' + lane)
        receipts[lane] = (receipt_path, report_path, report_rows)
    require(set(policies) == {x['caseID'] for x in cases}, 'study and policy memberships differ')
    rows = []
    for case in cases:
        identity = case['caseID']
        previous = by_id[identity]
        require(not previous['selected'] and previous['qualificationComparison'] == 'not-executed', 'baseline admission changed: ' + identity)
        for field in ('sourceLocation', 'sourceDigest', 'parserMode', 'renderMode', 'featureTags'):
            require(case[field] == previous[field], 'baseline ' + field + ' drift: ' + identity)
        fixture = args.spec_path / case['sourceLocation']['file']
        require(digest(fixture) == case['sourceDigest'], 'fixture digest changed: ' + identity)
        policy_name, lane, policy_sha = policies[identity]
        receipt_path, report_path, report_rows = receipts[lane]
        observation = report_rows[identity]
        require(observation['sourceDigest'] == case['sourceDigest'] and observation['parserMode'] == case['parserMode'] and observation['renderMode'] == case['renderMode'], 'targeted observation drift: ' + identity)
        samples = observation.get('samples', [observation])
        require(all(s['swift']['passed'] and s['reference']['passed'] for s in samples), 'targeted mismatch: ' + identity)
        rows.append({'caseID': identity, 'sourceLocation': case['sourceLocation'], 'sourceDigest': case['sourceDigest'],
                     'parserMode': case['parserMode'], 'renderMode': case['renderMode'], 'featureTags': case['featureTags'],
                     'fixture': case['fixture'], 'constructors': case['constructors'], 'requiredCapabilities': case['requiredCapabilities'],
                     'policy': policy_name, 'policySHA256': policy_sha, 'targetedLane': lane,
                     'targetedReceiptSHA256': digest(receipt_path), 'targetedReportSHA256': digest(report_path),
                     'targetedSampleCount': len(samples), 'baselineSelected': False,
                     'proposedAdmission': 'pending-safe-materialization-and-full-qualification'})
    result = {'schemaVersion': 1, 'status': 'PROPOSED_NOT_ADMITTED',
              'baselineMatrixSHA256': digest(args.baseline_matrix), 'studySHA256': digest(STUDY), 'cases': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2, ensure_ascii=False)
        stream.write('\n')
    print('Reconciled', len(rows), 'held identities across', len(NAMES), 'source-qualified targeted lanes')


if __name__ == '__main__':
    main()
