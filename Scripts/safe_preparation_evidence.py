#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fail closed when runner outcomes diverge from its inert preparation."""


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
        if original['generated'] != (row.get('expectationMaterialization') == 'deferred-excluded-generator'):
            raise ValueError('Fixture generator state differs: ' + case)
        if original['generated'] and row['selected']:
            raise ValueError('Generated fixture was unexpectedly selected: ' + case)
    return True
