#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fail closed on quote profile drift; never rewrite raw reference evidence."""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = ROOT / 'Tests/LiquidTests/Fixtures/QuotedStringReferenceCases.json'
EXPANDED = ROOT / 'Tests/LiquidTests/Fixtures/LaxQuoteRecoveryCases.json'
POLICY = ROOT / 'Tests/LiquidTests/Fixtures/SL21-02A4-ReviewedPolicy.json'
DISPOSITIONS = ROOT / 'Documentation/ControlTower/SL21-02A3-DISPOSITIONS.json'
PINS = {'original': '916ca2210913e36f8ebb5fa8c3da90ef243462bcdee85f14c3c491ad6cba597b',
        'expanded': '02c08497c74922972fb59db110dba32e1be7f95f8c23ee9d97f5c69f0ae50972',
        'policy': '1352e4b864c1455c41bb665f45bbe921c18d2fa16a7e4bf9b0c8ccd80773705f'}

def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value: raise ValueError('duplicate JSON key: ' + key)
        value[key] = item
    return value

def load(path):
    return json.loads(path.read_bytes(), object_pairs_hook=unique_object,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite JSON')))

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def keyed(rows, key):
    result = {}
    for row in rows:
        identity = key(row)
        if identity in result: raise ValueError('duplicate case identity: ' + str(identity))
        result[identity] = row
    return result

def main():
    for name, path in [('original', ORIGINAL), ('expanded', EXPANDED), ('policy', POLICY)]:
        if sha(path) != PINS[name]: raise ValueError(name + ' fixture or policy digest changed')
    originals, expanded, policy, previous = load(ORIGINAL), load(EXPANDED), load(POLICY), load(DISPOSITIONS)
    if policy['schemaVersion'] != 1 or policy['status'] != 'APPROVED_NARROW_SCOPE': raise ValueError('wrong reviewed scope')
    if policy['originalFixtureSHA256'] != PINS['original'] or policy['expandedFixtureSHA256'] != PINS['expanded']:
        raise ValueError('policy fixture pin changed')
    matrices = {}
    for name, source, expected in [('original', originals, 96), ('expanded', expanded, 75)]:
        matrices[name] = keyed(source['cases'], lambda r: (r['mode'], r['name']))
        if len(matrices[name]) != expected: raise ValueError('wrong raw matrix population: ' + name)
    rows = keyed(policy['rows'], lambda r: (r['profile'], r['id']))
    if len(rows) != 25: raise ValueError('wrong reviewed observation count')
    previous_rows = keyed(previous['rows'], lambda r: r['variantID'])
    expected_original = {'lax/single_escaped_delimiter', 'lax/double_escaped_delimiter', 'lax/single_unterminated', 'lax/double_unterminated'}
    if {identity for profile, identity in rows if profile == 'original'} != expected_original:
        raise ValueError('original reviewed identities changed')
    if {identity for profile, identity in rows if profile == 'expanded'} != set(previous_rows):
        raise ValueError('expanded reviewed identities changed')
    for (profile, identity), row in rows.items():
        mode, name = identity.split('/', 1)
        raw = matrices[profile][(mode, name)]
        expected = {k: raw.get(k) for k in ['phase', 'outcome', 'outputBytes', 'errorClass', 'message', 'line']}
        if row['sourceBytes'] != raw['sourceBytes'] or row['reference'] != expected:
            raise ValueError('raw reference or identity changed: ' + profile + '/' + identity)
        if row['context'] != ('empty' if profile == 'original' else 'fixed_lookup_context'):
            raise ValueError('context changed: ' + identity)
        if profile == 'original' or previous_rows[identity]['classification'] == 'UNRESOLVED_BEHAVIOR':
            if row['disposition'] != 'DEFERRED_RECOVERY' or row['swift']['phase'] != 'parse' or row['swift']['outcome'] != 'syntax-error':
                raise ValueError('deferred recovery must require syntax rejection: ' + identity)
            if not isinstance(row['swift'].get('message'), str): raise ValueError('missing syntax message')
        else:
            expected_output = [125, 125] if name == 'adjacent_output_delimiter' else [37, 125] if name == 'adjacent_tag_delimiter' else None
            if row['disposition'] != 'APPROVED_INERT_FRAMING' or row['swift'] != {'phase':'render','outcome':'output','outputBytes':expected_output}:
                raise ValueError('unapproved framing behavior: ' + identity)
    counts = policy['observations']
    if counts != {'original':96,'expanded':75,'reviewedObservations':25,'overlappingSourceModePairs':3,
                  'uniqueReviewedSourceModeIdentities':22,'approvedFraming':6,'expandedDeferred':15,'originalDeferred':4}:
        raise ValueError('reviewed accounting changed')
    overlap = []
    for (p, oid), a in rows.items():
        if p != 'original': continue
        for (q, eid), b in rows.items():
            if q == 'expanded' and oid.split('/')[0] == eid.split('/')[0] and a['sourceBytes'] == b['sourceBytes']:
                overlap.append({'original':oid,'expanded':eid,'identityBasis':'mode and exact source bytes','contextsDistinct':a['context'] != b['context']})
    if sorted(overlap, key=lambda x:x['original']) != sorted(policy['overlap'], key=lambda x:x['original']):
        raise ValueError('source/context overlap changed')
    tool = ROOT / 'Tools/QuotedStringRawTests/Tests/QuotedStringRawTests'
    for filename, function in [('QuotedStringCompatibilityTests.swift','referenceBytesAndParsePhase'), ('LaxQuoteRecoveryReferenceTests.swift','recoveryPhaseAndBytes')]:
        raw = (tool / filename).read_text()
        expected = raw.replace('    @Test(arguments: [LiquidSyntaxMode.lax, .strict, .strict2])\n    func ' + function,
                               '    func ' + function, 1)
        if expected != (ROOT / 'Tests/LiquidTests' / filename).read_text():
            raise ValueError('raw test assertion or relocation changed: ' + filename)
    for source in [ORIGINAL, EXPANDED]:
        if (tool / 'Fixtures' / source.name).read_bytes() != source.read_bytes(): raise ValueError('raw fixture copy changed')
    print(json.dumps({'status':'POLICY_VALIDATED_NOT_A_RAW_PASS','fixturePins':PINS,'accounting':counts,'overlap':overlap}, indent=2))

if __name__ == '__main__':
    try: main()
    except (OSError, KeyError, TypeError, ValueError) as error:
        print('quoted-literal review failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
