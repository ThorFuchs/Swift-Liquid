# SPDX-License-Identifier: Apache-2.0
"""Supplemental error evidence. Never changes an upstream verdict or suite data."""
import hashlib
import json
import re

TOKENS = {'(': 'open_round', ')': 'close_round', '[': 'open_square', ']': 'close_square',
          ':': 'colon', ',': 'comma', '.': 'dot', '..': 'dotdot', '|': 'pipe', '-': 'dash',
          '?': 'question', '%}': 'end_of_string', '}}': 'end_of_string', 'identifier': 'id',
          '==': 'comparison', '!=': 'comparison', '>': 'comparison', '<': 'comparison',
          '>=': 'comparison', '<=': 'comparison', '<>': 'comparison', 'contains': 'comparison'}


def token(raw):
    raw = raw.strip()
    for prefix, name in [('identifier(', 'id'), ('number(', 'number'), ('string(', 'string')]:
        if raw.startswith(prefix):
            return name
    return TOKENS.get(raw, raw)


def condition(message):
    """Extract only explicit conditions; a generic token error is incomplete evidence."""
    if not message:
        return {'kind': 'not-established'}
    match = re.search(r'Expected (.*?) but found (.*?)(?: in [\"\']|$)', message)
    if match:
        return {'kind': 'expected-token', 'expectedToken': token(match[1]), 'foundToken': token(match[2])}
    match = re.search(r'Unexpected token: (.*)', message)
    if match:
        return {'kind': 'generic-token', 'foundToken': token(match[1])}
    match = re.search(r"Unexpected character (.*?)(?: in [\"\']|$)", message)
    if match:
        return {'kind': 'unexpected-character', 'character': match[1].strip("'\"")}
    match = re.search(r"Unknown tag ['\"]([^'\"]+)['\"]", message)
    if match:
        return {'kind': 'unknown-tag', 'tag': match[1]}
    match = re.search(r"Unclosed tag ['\"]([^'\"]+)['\"]|['\"]([^'\"]+)['\"] tag was never closed", message)
    if match:
        return {'kind': 'unclosed-tag', 'tag': match[1] or match[2]}
    if 'Bare bracket access is not allowed' in message:
        return {'kind': 'bare-bracket-forbidden'}
    if 'Invalid attribute in for loop' in message or 'Invalid for loop parameter' in message:
        return {'kind': 'invalid-for-attribute'}
    if 'Syntax Error in \'assign\'' in message or 'Invalid assignment target' in message:
        return {'kind': 'invalid-assignment'}
    match = re.search(r'Expected (identifier|number|string literal|expression)(?:$| in )', message)
    if match:
        return {'kind': 'incomplete-expected-token', 'expectedToken': token(match[1].replace(' literal', ''))}
    return {'kind': 'not-established'}


def phase_compatible(expected, observed):
    if expected in ['parse-error', 'render-error']:
        return expected == observed
    if expected == 'output':
        return observed in ['successful-render', 'recovered-error']
    if expected == 'recovered-error-or-output-pattern':
        return observed in ['successful-render', 'recovered-error']
    return None


def dimensions(row):
    detail = row.get('reportedErrors')
    actual = detail if isinstance(detail, dict) else {}
    ref_detail = row.get('referenceReportedErrors')
    reference = ref_detail if isinstance(ref_detail, dict) else {}
    actual_condition = condition(actual.get('message'))
    reference_condition = condition(reference.get('message'))
    established = {'expected-token', 'unexpected-character', 'unknown-tag', 'unclosed-tag',
                   'bare-bracket-forbidden', 'invalid-for-attribute', 'invalid-assignment'}
    reason = 'not-established'
    if actual_condition['kind'] in established and reference_condition['kind'] in established:
        reason = 'same-reference-condition' if actual_condition == reference_condition else 'different-reference-condition'
    expected_errors = (row.get('expectation') or {}).get('errors', {})
    expected_line = expected_errors.get('line')
    expected_column = expected_errors.get('position')
    patterns = row.get('diagnosticEvidence', {}).get('messagePatternsMatch')
    location = row.get('diagnosticEvidence', {}).get('locationMatch')
    classification = 'not-applicable'
    if row['expectedCategory'] == 'parse-error' and row['observedCategory'] == 'parse-error':
        if row.get('upstreamVerdict', {}).get('passed') is True:
            classification = 'upstream-matched'
        elif patterns is True and location is False:
            classification = 'span-requirement'
        elif reason == 'same-reference-condition':
            classification = 'same-condition-wording-or-format'
        elif reason == 'different-reference-condition':
            classification = 'different-reference-rejection-reason'
        else:
            classification = 'reason-not-established-or-incomplete'
    rendered = row.get('renderedOutput')
    if rendered is None and row['observedCategory'] in ['successful-render', 'recovered-error'] and isinstance(row.get('actual'), str):
        rendered = row['actual']
    return {'parseAcceptance': (True if row.get('compileOutcome') == 'compiled' else False if row['observedCategory'] == 'parse-error' else None) if row['selected'] else None,
            'phaseCompatible': phase_compatible(row['expectedCategory'], row['observedCategory']) if row['selected'] else None,
            'expectedPhase': row['expectedCategory'], 'observedPhase': row['observedCategory'],
            'errorFamily': 'syntax' if actual.get('type') == 'syntax_error' else 'runtime-unspecified' if actual.get('type') == 'render_error' else actual.get('type'),
            'referenceErrorFamily': 'syntax' if reference.get('type', '').endswith('SyntaxError') else reference.get('type'),
            'actualCondition': actual_condition, 'referenceCondition': reference_condition,
            'reasonEquivalence': reason, 'diagnosticClassification': classification,
            'exactMessagePatternMatch': patterns, 'upstreamLocationMatch': location,
            'line': {'expected': expected_line, 'swift': actual.get('line'), 'ruby': reference.get('line')},
            'column': {'expected': expected_column, 'swift': actual.get('column'), 'ruby': reference.get('column')},
            'renderedBytes': len(rendered.encode('utf-8')) if isinstance(rendered, str) else None,
            'renderedSHA256': hashlib.sha256(rendered.encode('utf-8')).hexdigest() if isinstance(rendered, str) else None,
            'recoveredOutput': rendered if row['observedCategory'] == 'recovered-error' else None,
            'errorFreeRender': row['observedCategory'] == 'successful-render' if row['observedCategory'] in ['successful-render', 'recovered-error'] else None,
            'policy': 'Supplemental only; no condition equivalence changes the pinned comparator verdict.'}
