#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fail closed when runner outcomes diverge from its inert preparation."""
import hashlib
import json


def check(rows, preparation):
    if preparation.get('status') != 'INERT_INVENTORY_NOT_QUALIFICATION':
        raise ValueError('Fixture preparation status changed')
    prepared = preparation['variants']
    indexed = {row['caseID']: row for row in prepared}
    if len(indexed) != len(prepared) or len(rows) != len(prepared) or len({r['caseID'] for r in rows}) != len(rows):
        raise ValueError('Fixture preparation identity population differs')
    for row in rows:
        case = row['caseID']
        if case not in indexed:
            raise ValueError('Fixture preparation identity missing: ' + case)
        original = indexed[case]
        if any(row[key] != original[key] for key in ('sourceLocation', 'sourceDigest', 'parserMode', 'renderMode', 'featureTags')):
            raise ValueError('Fixture preparation metadata differs: ' + case)
        selection = original['selection']
        if row['selected'] != selection['selected'] or row.get('admission') != selection['admission']:
            raise ValueError('Fixture preparation selection differs: ' + case)
        if not row['selected'] and (row['reason'] != selection['reason'] or row['comparison'] != 'not-executed' or row['qualificationComparison'] != 'not-executed'):
            raise ValueError('Excluded fixture has an inconsistent result: ' + case)
        generator_state = row.get('expectationMaterialization')
        if original['generated']:
            expected_state = ('historical-seeded-closed-materialization' if row['selected'] and
                              row.get('admission') == 'guarded_standard_drop' else 'deferred-excluded-generator')
            if generator_state != expected_state:
                raise ValueError('Fixture generator state differs: ' + case)
            if row['selected'] and row['expectation'] != original['materialized']['expectation']:
                raise ValueError('Generated expectation differs from preparation: ' + case)
            if row['selected']:
                allowed = {
                    'basics/specs/basics/drops.yml:174/drop_method_square_random/strict2/raise': (28, '{{ drop.square_28 }}', '784'),
                    'basics/specs/basics/drops.yml:191/drop_method_echo_random/strict2/raise': (705, '{{ drop.echo_705 }}', '705'),
                }
                if case not in allowed:
                    raise ValueError('Unapproved generated fixture: ' + case)
                number, template, output = allowed[case]
                encoded = json.dumps(template, ensure_ascii=False, separators=(',', ':')).encode()
                if (original.get('generatedInput') != number or row['expectation']['output'] != output or
                        original['materialized']['template'] != {'jsonBytes': len(encoded), 'sha256': hashlib.sha256(encoded).hexdigest()}):
                    raise ValueError('Generated input or template changed: ' + case)
        elif generator_state is not None:
            raise ValueError('Unexpected fixture generator state: ' + case)
    return True
