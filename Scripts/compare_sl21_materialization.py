#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare safe prepared inputs to available, source-bound historical traces."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from ci import source_revision

PIN = '84bf25e0edbca5f7e530574788b0f875ab331f50'
RUBY_PIN = '4e39ae4cc3da73921923c0669e0fc84a66b2f696'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def index_unique(rows):
    result = {row['caseID']: row for row in rows}
    if len(result) != len(rows):
        raise ValueError('Duplicate case identity')
    return result


def read_traces(path):
    result = {}
    with path.open() as stream:
        for line in stream:
            item = json.loads(line)
            if item.get('direction') != 'request' or not item.get('case'):
                continue
            message = item['message']
            method = message.get('method')
            if method not in ('compile', 'render'):
                continue
            case = result.setdefault(item['case'], {})
            if method in case:
                raise ValueError('Duplicate historical request for ' + item['case'])
            case[method] = message['params']
    return result


def compare(inventory, earlier, traces, current=None, current_traces=None):
    now = index_unique(inventory['variants'])
    old = index_unique(earlier)
    if len(now) != 5112 or set(now) != set(old):
        raise ValueError('Identity population differs')
    fresh = index_unique(current) if current is not None else None
    if fresh is not None and set(fresh) != set(now):
        raise ValueError('Fresh identity population differs')
    rows = []
    for case, item in sorted(now.items()):
        previous = old[case]
        if any(item[key] != previous[key] for key in ('sourceDigest', 'sourceLocation', 'parserMode', 'renderMode', 'featureTags')):
            raise ValueError('Historical identity differs: ' + case)
        prepared = item['materialized']
        selected = item['selection']['selected']
        current_row = fresh[case] if fresh is not None else None
        if current_row is not None and (current_row['selected'] != selected or any(current_row[key] != item[key] for key in ('sourceDigest', 'sourceLocation', 'parserMode', 'renderMode', 'featureTags'))):
            raise ValueError('Fresh identity or selection differs: ' + case)
        if not selected:
            if prepared is not None:
                raise ValueError('Excluded fixture was materialized: ' + case)
            rows.append({'caseID': case, 'selection': 'unexecuted', 'materialization': 'not-invoked'})
            continue
        if prepared is None:
            raise ValueError('Selected fixture was not prepared: ' + case)
        fresh_checks = None
        if current_row is not None:
            if current_row['expectation'] != prepared['expectation']:
                raise ValueError('Fresh expectation differs: ' + case)
            fresh_checks = {'swiftQualification': current_row['qualificationComparison'],
                            'rubyQualification': current_row['referenceQualificationComparison'],
                            'swiftCategory': current_row['observedCategory'],
                            'rubyCategory': current_row['referenceObservedCategory'],
                            'swiftVerdict': current_row['upstreamVerdict'],
                            'rubyVerdict': current_row['referenceUpstreamVerdict']}
            trace = (current_traces or {}).get(case, {})
            for field, method in (('template', 'compile'), ('filesystem', 'compile'), ('environment', 'render')):
                wire = trace.get(method, {}).get(field)
                if wire is None:
                    fresh_checks[field] = 'unavailable-no-fresh-request'
                elif all(wire.get(key) == prepared[field][key] for key in ('sha256', 'jsonBytes')):
                    fresh_checks[field] = 'matched-fresh-wire-digest'
                else:
                    raise ValueError('Fresh wire digest differs for ' + case + ': ' + field)
        if not previous['selected']:
            rows.append({'caseID': case, 'selection': 'selected', 'materialization': 'prepared',
                         'historicalEvidence': 'unavailable-earlier-exclusion', 'preparedInputs': prepared,
                         'freshEvidence': fresh_checks})
            continue
        trace = traces.get(case, {})
        checks = {}
        for field, method in (('template', 'compile'), ('filesystem', 'compile'), ('environment', 'render')):
            historical = trace.get(method, {}).get(field)
            if historical is None:
                checks[field] = 'unavailable-no-historical-request'
            elif all(historical.get(key) == prepared[field][key] for key in ('sha256', 'jsonBytes')):
                checks[field] = 'matched-historical-wire-digest'
            else:
                raise ValueError('Historical wire digest differs for ' + case + ': ' + field)
        if prepared['expectation'] != previous['expectation']:
            raise ValueError('Historical fixture expectation differs: ' + case)
        checks['expectation'] = 'matched-earlier-matrix'
        phase = {key: previous.get(key) for key in ('expectedCategory', 'observedCategory', 'compileOutcome', 'qualificationComparison')}
        if checks['environment'] == 'unavailable-no-historical-request':
            if phase['compileOutcome'] == phase['observedCategory'] == 'parse-error':
                phase['absentRenderReason'] = 'expected-parse-error' if phase['expectedCategory'] == 'parse-error' else 'unexpected-parse-error'
            elif phase['observedCategory'] in ('operational-error', 'protocol-error', 'domain-divergence'):
                phase['absentRenderReason'] = 'operational-failure'
            else:
                phase['absentRenderReason'] = 'missing-or-unexplained-evidence'
        rows.append({'caseID': case, 'selection': 'selected', 'materialization': 'prepared',
                     'historicalEvidence': 'earlier-source-bound-receipt', 'checks': checks, 'historicalPhase': phase,
                     'freshEvidence': fresh_checks})
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--historical-matrix', type=Path, required=True)
    parser.add_argument('--historical-traces', type=Path, required=True)
    parser.add_argument('--historical-receipt', type=Path, required=True)
    parser.add_argument('--current-receipt', type=Path, help='Clean current independent receipt; optional for historical-only comparison')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit('Refusing to overwrite materialization comparison')
    receipt = json.loads(args.historical_receipt.read_text())
    report_hashes = receipt['reportSHA256']
    if (receipt['pins'] != {'spec': PIN, 'ruby': RUBY_PIN} or not receipt['sourceQualified'] or not receipt['sourceUnchanged']
            or report_hashes['ELIGIBILITY_MATRIX.json'] != sha(args.historical_matrix)
            or report_hashes['RPC_TRACES.jsonl'] != sha(args.historical_traces)):
        raise ValueError('Historical receipt or evidence checksum invalid')
    inventory = json.loads(args.inventory.read_text())
    if inventory['specPin'] != PIN:
        raise ValueError('Inventory pin differs')
    current_rows = current_traces = None
    current_info = None
    if args.current_receipt:
        current_info = json.loads(args.current_receipt.read_text())
        reports = args.current_receipt.parent / 'spec'
        matrix_path = reports / 'ELIGIBILITY_MATRIX.json'
        trace_path = reports / 'RPC_TRACES.jsonl'
        if (current_info['pins'] != {'spec': PIN, 'ruby': RUBY_PIN} or not current_info['sourceQualified'] or not current_info['sourceUnchanged']
                or current_info['sourceRevision'] != source_revision() or current_info['endingSourceRevision'] != source_revision()
                or current_info['reportSHA256']['ELIGIBILITY_MATRIX.json'] != sha(matrix_path)
                or current_info['reportSHA256']['RPC_TRACES.jsonl'] != sha(trace_path)):
            raise ValueError('Fresh receipt or evidence checksum invalid')
        current_rows = json.loads(matrix_path.read_text())
        current_traces = read_traces(trace_path)
    rows = compare(inventory, json.loads(args.historical_matrix.read_text()), read_traces(args.historical_traces), current_rows, current_traces)
    totals = Counter(row['historicalEvidence'] for row in rows if 'historicalEvidence' in row)
    checks = Counter((field, result) for row in rows for field, result in row.get('checks', {}).items())
    summary = {field + ':' + result: count for (field, result), count in sorted(checks.items())}
    absent = Counter(row.get('historicalPhase', {}).get('absentRenderReason') for row in rows
                     if row.get('historicalPhase', {}).get('absentRenderReason'))
    result = {'schemaVersion': 1, 'status': 'PARTIAL_HISTORICAL_MATERIALIZATION_COMPARISON',
              'limitations': 'Earlier receipt is not the 425-exclusion historical run. Missing historical render traces and 63 later admissions remain unverified against historical materialization; fresh evidence is separate.',
              'inputs': {'inventorySHA256': sha(args.inventory), 'matrixSHA256': sha(args.historical_matrix),
                         'tracesSHA256': sha(args.historical_traces), 'receiptSHA256': sha(args.historical_receipt),
                         'earlierSourceRevision': receipt['sourceRevision']},
              'summary': {'historicalEvidence': dict(totals), 'checks': summary, 'absentHistoricalRenders': dict(absent)}, 'rows': rows}
    if current_info is not None:
        result['inputs']['currentReceiptSHA256'] = sha(args.current_receipt)
        result['inputs']['currentSourceRevision'] = current_info['sourceRevision']
        result['summary']['freshLaterAdmissions'] = dict(Counter(row['freshEvidence']['swiftQualification'] + '/' + row['freshEvidence']['rubyQualification']
            for row in rows if row.get('historicalEvidence') == 'unavailable-earlier-exclusion'))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps(result['summary'], sort_keys=True))


if __name__ == '__main__':
    main()
