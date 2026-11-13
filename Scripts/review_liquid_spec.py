#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Admit exact reviewed reference conflicts without changing upstream verdicts."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

from analyze_liquid_spec import audit
from ci import ROOT, source_revision, source_snapshot

POLICY = ROOT / 'Tools/LiquidSpecAdapter/ReviewedConflicts.json'
CANDIDATES = ROOT / 'Tools/LiquidSpecAdapter/ExclusionCandidates.json'
REPORTS = ('ELIGIBILITY_MATRIX.json', 'SPEC_RUNS.json',
           'PHASE_AND_DIAGNOSTIC_LEDGER.json', 'RPC_TRACES.jsonl')
COMMANDS = {'spec-pin.log', 'spec-clean.log', 'ruby-pin.log', 'ruby-clean.log',
            'swift-version.log', 'ruby-version.log', 'adapter-build.log',
            'adapter-location.log', 'protocol-tests.log', 'bridge-tests.log',
            'diagnostic-evidence-tests.log', 'liquid-spec-runner.log', 'diagnostic-ledger.log'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def eligibility_digest(rows):
    fields = ('caseID', 'selected', 'reason', 'featureTags', 'parserMode', 'renderMode',
              'sourceLocation', 'sourceDigest', 'expectation')
    value = [{key: row.get(key) for key in fields} for row in sorted(rows, key=lambda row: row['caseID'])]
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()


def evaluate(rows, policy):
    """Fail on a stale conflict, changed population, hidden operation, or new failure."""
    audit(rows)  # Validates unique identities and preserves unmodified raw verdicts.
    if len(rows) != policy['expectedPopulation'] or eligibility_digest(rows) != policy['eligibilitySHA256']:
        raise ValueError('Fixture identities, eligibility, or expectations changed; review required')
    conflicts = {item['caseID']: item for item in policy['conflicts']}
    if len(conflicts) != 5 or len(policy['conflicts']) != 5:
        raise ValueError('Exactly five distinct reviewed conflicts are required')
    unresolved = []
    for row in rows:
        case = row['caseID']
        if not row['selected']:
            if row['comparison'] != 'not-executed' or row['qualificationComparison'] != 'not-executed' or row['observedCategory'] == 'operational-error':
                raise ValueError('Unselected case has inconsistent or operational outcome')
            continue
        if row['qualificationComparison'] == 'matched':
            if case in conflicts:
                raise ValueError('A reviewed conflict now passes; review its removal')
            continue
        if case not in conflicts:
            unresolved.append(case)
            continue
        expected = conflicts[case]
        if any(row.get(key) != value for key, value in expected.items()):
            raise ValueError('Reviewed conflict changed: ' + case)
        if (row['comparison'] != 'mismatched' or row['qualificationComparison'] != 'mismatched'
                or row.get('referenceComparison') != 'mismatched'
                or row.get('referenceQualificationComparison') != 'mismatched'
                or row['upstreamVerdict'].get('passed') is not False
                or row.get('referenceUpstreamVerdict', {}).get('passed') is not False):
            raise ValueError('Conflict does not retain both failed raw/reference verdicts: ' + case)
    if unresolved:
        raise ValueError('Unreviewed failures: ' + ', '.join(unresolved[:10]))
    if {row['caseID'] for row in rows if row['caseID'] in conflicts and row['selected']} != set(conflicts):
        raise ValueError('Reviewed conflict missing or unselected')
    excluded = [row for row in rows if not row['selected']]
    return {'status': 'passed-with-reviewed-reference-conflicts',
            'rawStatus': 'failed', 'unexpectedFailures': 0,
            'matched': sum(row['selected'] and row['qualificationComparison'] == 'matched' for row in rows),
            'reviewedConflicts': len(conflicts), 'notExecuted': len(excluded),
            'referenceConcerns': [row['caseID'] for row in rows if row['selected'] and row.get('referenceQualificationComparison') != 'matched'],
            'excludedByCategory': dict(Counter(row['observedCategory'] for row in excluded)),
            'excludedByReason': dict(Counter(row['reason'] for row in excluded)),
            'issue': policy['issue']}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True, help='Independent raw receipt directory')
    parser.add_argument('--spec-path', type=Path, required=True)
    parser.add_argument('--reference-path', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    output = {'status': 'failed', 'rawStatus': 'unknown'}
    try:
        policy = json.loads(POLICY.read_text())
        env = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1', GIT_NO_REPLACE_OBJECTS='1', GIT_TERMINAL_PROMPT='0')
        for key, checkout in [('spec', args.spec_path), ('ruby', args.reference_path)]:
            def git(*parts):
                return subprocess.check_output(['git', '--no-optional-locks', '-c', 'core.fsmonitor=false',
                                                '-C', str(checkout), *parts], env=env, text=True).strip()
            if git('rev-parse', 'HEAD') != policy['pins'][key] or git('status', '--porcelain'):
                raise ValueError('Pinned reference moved or became dirty: ' + key)
        receipt_path = args.input / 'receipt.json'
        receipt = json.loads(receipt_path.read_text())
        revision = source_revision()
        if (not revision.get('clean') or receipt.get('status') != 'failed' or receipt.get('runnerExitCode') != 1
                or receipt.get('error') != 'Independent conformance gate has mismatches or operational errors; see exact matrix'
                or receipt.get('pins') != policy['pins'] or not receipt.get('sourceUnchanged')
                or not receipt.get('sourceQualified') or receipt.get('sourceRevision') != revision
                or receipt.get('endingSourceRevision') != revision or receipt.get('sources') != source_snapshot()):
            raise ValueError('Raw receipt, pinned references, or clean source binding invalid')
        commands = receipt['commands']
        if len(commands) != len(COMMANDS) or {c['log'] for c in commands} != COMMANDS:
            raise ValueError('Raw lane command inventory changed')
        for command in commands:
            name = command['log']
            if command['exitCode'] != (1 if name == 'liquid-spec-runner.log' else 0) or not (args.input / name).is_file():
                raise ValueError('Raw lane contains a missing or failed prerequisite: ' + name)
        reports = args.input / 'spec'
        if set(receipt['reportSHA256']) != set(REPORTS):
            raise ValueError('Raw report inventory changed')
        for name in REPORTS:
            if sha(reports / name) != receipt['reportSHA256'][name]:
                raise ValueError('Raw report checksum mismatch: ' + name)
        runs = json.loads((reports / 'SPEC_RUNS.json').read_text())
        rows = json.loads((reports / 'ELIGIBILITY_MATRIX.json').read_text())
        if (runs['observedRows'] != len(rows) or runs['shutdownError'] is not None
                or sum(suite['expandedVariants'] for suite in runs['suites']) != len(rows)):
            raise ValueError('Runner population or shutdown incomplete')
        # Each case is bound to the actual pinned file, including unexecuted cases.
        spec_root = args.spec_path.resolve()
        file_digests = {}
        for row in rows:
            relative = row['sourceLocation']['file']
            path = (spec_root / relative).resolve()
            if not path.is_relative_to(spec_root) or not path.is_file():
                raise ValueError('Invalid fixture path: ' + relative)
            if relative not in file_digests:
                file_digests[relative] = sha(path)
            if file_digests[relative] != row['sourceDigest']:
                raise ValueError('Fixture bytes changed: ' + relative)
        output = evaluate(rows, policy)
        candidates = json.loads(CANDIDATES.read_text())
        if candidates['specPin'] != policy['pins']['spec']:
            raise ValueError('Exclusion candidate pin changed')
        candidate_rows = candidates['filesystemCandidates'] + candidates['rangeMetadataCandidates']
        by_id = {row['caseID']: row for row in rows}
        if len(candidate_rows) != 58 or len({item['caseID'] for item in candidate_rows}) != 58:
            raise ValueError('Exclusion candidate membership changed')
        for item in candidate_rows:
            row = by_id.get(item['caseID'])
            if row is None or not row['selected'] or row['sourceDigest'] != item['sourceDigest']:
                raise ValueError('Admission candidate no longer matches pinned evidence')
            group = 'unused_filesystem_callback' if item in candidates['filesystemCandidates'] else 'unused_resource_limits'
            if row.get('admission') != group:
                raise ValueError('Candidate admission rationale missing or changed')
        admitted = [{'caseID': by_id[item['caseID']]['caseID'], 'sourceDigest': item['sourceDigest'],
                     'sourceLocation': by_id[item['caseID']]['sourceLocation'],
                     'admission': by_id[item['caseID']]['admission'],
                     'comparison': by_id[item['caseID']]['comparison'],
                     'qualificationComparison': by_id[item['caseID']]['qualificationComparison'],
                     'referenceQualificationComparison': by_id[item['caseID']]['referenceQualificationComparison']}
                    for item in candidate_rows]
        (args.output / 'ADMISSION_AUDIT.json').write_text(json.dumps(admitted, indent=2) + '\n')
        output.update(sourceRevision=revision, pins=policy['pins'], rawReceiptSHA256=sha(receipt_path),
                      rawMatrixSHA256=sha(reports / 'ELIGIBILITY_MATRIX.json'), policySHA256=sha(POLICY),
                      fixtureFiles=len(file_digests), admittedCandidates=58, candidatesSHA256=sha(CANDIDATES),
                      admissionAuditSHA256=sha(args.output / 'ADMISSION_AUDIT.json'))
        excluded = [{'caseID': row['caseID'], 'sourceLocation': row['sourceLocation'],
                     'sourceDigest': row['sourceDigest'], 'parserMode': row['parserMode'],
                     'renderMode': row['renderMode'], 'featureTags': row['featureTags'], 'reason': row['reason'],
                     'category': row['observedCategory'],
                     'review': ('reassess-overbroad-selection' if ('custom filesystem error callback' in row['reason'] or 'range_resource_limits' in row['reason'])
                                else 'tag-based-selection-requires-case-review' if any(tag in row['reason'] for tag in ('ruby_drops:', 'drops:', 'drop_class_output:'))
                                else 'current-adapter-boundary-not-conformance')}
                    for row in rows if not row['selected']]
        (args.output / 'EXCLUSION_AUDIT.json').write_text(json.dumps(excluded, indent=2) + '\n')
        output['exclusionAuditSHA256'] = sha(args.output / 'EXCLUSION_AUDIT.json')
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        output['status'] = 'failed'
        output['error'] = str(error)
    (args.output / 'REVIEWED_RESULT.json').write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps(output, sort_keys=True))
    return 0 if output['status'] == 'passed-with-reviewed-reference-conflicts' else 1


if __name__ == '__main__':
    sys.exit(main())
