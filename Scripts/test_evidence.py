# SPDX-License-Identifier: Apache-2.0
"""Fail-closed admission of Swift Testing v0 events; no human-message parsing.

Case identity uses the Swift 6.4 adapter's underscored metadata. A changed adapter
must be qualified explicitly; this is not a promise of stability for those fields.
"""
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('Duplicate JSON member')
        value[key] = item
    return value


def invalid_constant(value):
    raise ValueError(f'Non-JSON numeric constant: {value}')


def identity(test_id):
    if not isinstance(test_id, str) or not re.search(r'/[^/]+\.swift:\d+:\d+$', test_id):
        raise ValueError('Unrecognized Swift test-function identity')
    return test_id.rsplit('/', 1)[0]


def analyze(path, expected, exit_code=0):
    report = {'schemaVersion': 1, 'eventStreamVersion': 0, 'status': 'failed',
              'exitCode': exit_code, 'errors': [], 'skipped': 0, 'issues': 0,
              'knownIssues': 0, 'cancellations': 0, 'skippedTests': [],
              'recordedIssues': [], 'cancelledTests': []}
    errors = report['errors']
    if not expected:
        errors.append('Empty expected function inventory')
    if exit_code != 0:
        errors.append(f'Test process exited with {exit_code}')
    try:
        raw = Path(path).read_bytes()
        report['eventsSHA256'] = hashlib.sha256(raw).hexdigest()
        if not raw or not raw.endswith(b'\n'):
            raise ValueError('Missing or truncated JSON Lines event stream')
        records = [json.loads(line, object_pairs_hook=unique_object, parse_constant=invalid_constant) for line in raw.splitlines()]
        # Count observed rejection events even if an earlier malformed declaration
        # prevents semantic admission (for example an empty parameter collection).
        for record in records:
            if not isinstance(record, dict) or record.get('kind') != 'event':
                continue
            payload = record.get('payload')
            if not isinstance(payload, dict):
                continue
            kind = payload.get('kind')
            if kind == 'testSkipped':
                report['skipped'] += 1
                report['skippedTests'].append(payload.get('testID'))
            elif kind == 'issueRecorded':
                report['issues'] += 1
                issue = payload.get('issue')
                known = bool(issue.get('isKnown')) if isinstance(issue, dict) else False
                report['knownIssues'] += int(known)
                case = payload.get('_testCase')
                report['recordedIssues'].append({'testID': payload.get('testID'),
                    'caseID': case.get('id') if isinstance(case, dict) else None, 'isKnown': known})
            elif kind in ['testCancelled', 'testCaseCancelled']:
                report['cancellations'] += 1
                report['cancelledTests'].append(payload.get('testID'))
        declarations, functions, cases = {}, {}, {}
        started, ended = Counter(), Counter()
        case_started, case_ended = Counter(), Counter()
        run_started = run_ended = 0
        for record in records:
            if not isinstance(record, dict):
                raise ValueError('Stream record must be an object')
            if type(record.get('version')) is not int or record['version'] != 0:
                raise ValueError('Unsupported event stream version')
            payload = record['payload']
            if not isinstance(payload, dict):
                raise ValueError('Stream payload must be an object')
            kind = payload['kind']
            if record['kind'] == 'test':
                if run_started or run_ended:
                    raise ValueError('Declaration after run start')
                test_id = payload['id']
                if test_id in declarations or kind not in ['function', 'suite']:
                    raise ValueError('Duplicate or unrecognized declaration')
                declarations[test_id] = payload
                if kind == 'function':
                    key = identity(test_id)
                    if key in functions:
                        raise ValueError('Colliding logical function identities')
                    functions[key] = test_id
                    if type(payload.get('isParameterized')) is not bool:
                        raise ValueError('Missing parameterization metadata')
                    if payload['isParameterized']:
                        identifiers = [case['id'] for case in payload['_testCases']]
                        if not identifiers or not all(isinstance(item, str) for item in identifiers) or len(set(identifiers)) != len(identifiers):
                            raise ValueError('Empty or duplicate parameterized case inventory')
                        cases[test_id] = set(identifiers)
                continue
            if record['kind'] != 'event':
                raise ValueError('Unrecognized stream record')
            if kind == 'runStarted':
                if run_started or run_ended:
                    raise ValueError('Duplicate or reversed run boundary')
                run_started += 1
                continue
            if not run_started or run_ended:
                raise ValueError('Event outside the run')
            if kind == 'runEnded':
                run_ended += 1
                continue
            if kind == 'issueRecorded':
                if not isinstance(payload.get('issue'), dict):
                    raise ValueError('Malformed recorded issue')
                continue
            if kind in ['testCancelled', 'testCaseCancelled']:
                continue
            if kind == 'valueAttached':
                continue
            test_id = payload['testID']
            if test_id not in declarations:
                raise ValueError('Event for an undeclared test')
            if kind == 'testSkipped':
                continue
            elif kind == 'testStarted':
                if started[test_id] or ended[test_id]:
                    raise ValueError('Duplicate or reversed test start')
                started[test_id] += 1
            elif kind == 'testEnded':
                if started[test_id] != 1 or ended[test_id]:
                    raise ValueError('Missing start or duplicate test completion')
                if any(case_started[(test_id, case)] != case_ended[(test_id, case)] for case in cases.get(test_id, [])):
                    raise ValueError('Test ended with an unfinished case')
                ended[test_id] += 1
            elif kind in ['testCaseStarted', 'testCaseEnded']:
                case_id = payload['_testCase']['id']
                if test_id not in cases or case_id not in cases[test_id]:
                    raise ValueError('Case absent from declared parameter inventory')
                if started[test_id] != 1 or ended[test_id]:
                    raise ValueError('Case event outside its function')
                key = (test_id, case_id)
                if kind == 'testCaseStarted':
                    if case_started[key] or case_ended[key]:
                        raise ValueError('Duplicate or reversed case start')
                    case_started[key] += 1
                else:
                    if case_started[key] != 1 or case_ended[key]:
                        raise ValueError('Missing start or duplicate case completion')
                    case_ended[key] += 1
            else:
                raise ValueError(f'Unrecognized event kind: {kind}')
        if run_started != 1 or run_ended != 1:
            errors.append('Incomplete run boundaries')
        if set(functions) != set(expected):
            errors.append(f'Function inventory mismatch: missing={sorted(set(expected) - set(functions))}, unexpected={sorted(set(functions) - set(expected))}')
        for key, test_id in functions.items():
            declared_count = len(cases[test_id]) if test_id in cases else None
            if key in expected and declared_count != expected[key]:
                errors.append(f'Parameter inventory mismatch: {key}: expected {expected[key]}, found {declared_count}')
        if any(started[test_id] != 1 or ended[test_id] != 1 for test_id in declarations):
            errors.append('Unexecuted or unfinished tests/suites')
        for test_id, identifiers in cases.items():
            if any(case_started[(test_id, case)] != 1 or case_ended[(test_id, case)] != 1 for case in identifiers):
                errors.append(f'Unexecuted or unfinished parameter cases: {identity(test_id)}')
        report.update(testFunctions=len(functions), suites=len(declarations) - len(functions),
                      completedFunctions=sum(ended[value] for value in functions.values()),
                      parameterizedCases=sum(map(len, cases.values())),
                      startedCases=sum(case_started.values()), completedCases=sum(case_ended.values()),
                      functions={key: {'parameterizedCases': len(cases[value]) if value in cases else None,
                                       'completed': ended[value] == 1,
                                       'completedCases': sum(case_ended[(value, case)] for case in cases.get(value, []))}
                                 for key, value in sorted(functions.items())})
    except (OSError, ValueError, KeyError, TypeError) as error:
        errors.append(str(error))
    for field in ['skipped', 'issues', 'cancellations']:
        if report[field]:
            errors.append(f'{field}: {report[field]}')
    if not errors:
        report['status'] = 'passed'
    return report


def qualify(path, inventory_path, profile, exit_code=0):
    try:
        raw_inventory = Path(inventory_path).read_bytes()
        inventory = json.loads(raw_inventory, object_pairs_hook=unique_object, parse_constant=invalid_constant)
        if not isinstance(inventory, dict) or inventory.get('schemaVersion') != 1:
            raise ValueError('Invalid reviewed test inventory version')
        expected = inventory['functions']
        if not isinstance(expected, dict) or not expected or any(
                not isinstance(key, str) or (value is not None and (type(value) is not int or value <= 0))
                for key, value in expected.items()):
            raise ValueError('Invalid reviewed function inventory')
        if profile in ['thread', 'adversarial']:
            selected = inventory[profile + 'Functions']
            if not isinstance(selected, list) or not selected or len(set(selected)) != len(selected):
                raise ValueError('Invalid selected-function inventory')
            expected = {key: expected[key] for key in selected}
        elif profile != 'full':
            raise ValueError('Unknown test evidence profile')
    except (OSError, ValueError, KeyError, TypeError) as error:
        result = analyze(path, {}, exit_code)
        result['errors'].append(f'Reviewed inventory: {error}')
    else:
        result = analyze(path, expected, exit_code)
        result['inventorySHA256'] = hashlib.sha256(raw_inventory).hexdigest()
    result['profile'] = profile
    return result
