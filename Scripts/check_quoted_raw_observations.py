#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Audit a failing raw reference run without relabeling its differences as passes."""
import argparse
import ast
import json
from pathlib import Path
import re
import sys
from test_evidence import analyze
from check_quoted_literal_review import load, ORIGINAL, EXPANDED, POLICY

EXPECTED = {
    'QuotedStringRawTests.QuotedStringCompatibilityTests/referenceBytesAndParsePhase(mode:)': 3,
    'QuotedStringRawTests.LaxQuoteRecoveryReferenceTests/recoveryPhaseAndBytes(mode:)': 3,
}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--events',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists(): raise ValueError('refusing to overwrite raw audit')
    event_report=analyze(args.events,EXPECTED,exit_code=1)
    if set(event_report['errors']) != {'Test process exited with 1','issues: 25'} or event_report['knownIssues'] or event_report['skipped'] or event_report['cancellations']:
        raise ValueError('raw event stream differs from known complete failing run: '+repr(event_report['errors']))
    matrices={'original':load(ORIGINAL)['cases'],'expanded':load(EXPANDED)['cases']}
    policy={(r['profile'],r['id']):r for r in load(POLICY)['rows']}
    observations={}
    for line in args.log.read_text().splitlines():
        m=re.match(r'(QUOTED-STRING|RECOVERY) (\S+) (\S+) (.*)',line)
        if not m:continue
        key=('original' if m[1]=='QUOTED-STRING' else 'expanded',m[2]+'/'+m[3])
        if key in observations:raise ValueError('duplicate raw observation '+repr(key))
        observations[key]=m[4]
    rows=[]
    for profile,items in matrices.items():
        for item in items:
            key=(profile,item['mode']+'/'+item['name'])
            if key not in observations:raise ValueError('missing raw observation '+repr(key))
            actual=observations[key]; reviewed=policy.get(key); outcome=item['outcome']; expected=item.get('outputBytes')
            if actual.startswith('output='):
                value=ast.literal_eval(actual[7:]); matched=outcome=='output' and value==expected
            elif actual.startswith('parse-error '):
                value=None; matched=outcome=='parse-error'
            elif actual.startswith('render-error'):
                value=None; matched=outcome=='render-error'
            elif actual=='parsed-unexpectedly':
                value=None; matched=False
            else:raise ValueError('unknown or operational observation '+repr(key)+': '+actual)
            if matched == (reviewed is not None):raise ValueError('unapproved raw status transition '+repr(key))
            if reviewed:
                swift=reviewed['swift']
                if reviewed['disposition']=='DEFERRED_RECOVERY':
                    line='nil' if swift['line'] is None else f"Optional({swift['line']})"
                    col='nil' if swift['column'] is None else f"Optional({swift['column']})"
                    target=f"parse-error line={line} column={col} message={swift['message']}"
                    if actual!=target:raise ValueError('deferred Swift rejection changed '+repr(key))
                elif reviewed['disposition']=='APPROVED_INERT_FRAMING':
                    if item['outcome']=='output':
                        if not actual.startswith('output=') or value!=swift['outputBytes']:raise ValueError('framing output changed '+repr(key))
                    elif actual!='parsed-unexpectedly':raise ValueError('framing parse changed '+repr(key))
                else:raise ValueError('unknown disposition '+repr(key))
            rows.append({'profile':profile,'id':key[1],'sourceBytes':item['sourceBytes'],
                         'reference':{k:item.get(k) for k in ['phase','outcome','outputBytes','errorClass','message','line']},
                         'swiftObservation':actual,'rawComparison':'matched' if matched else 'mismatched',
                         'reviewDisposition':reviewed['disposition'] if reviewed else None})
    if len(rows)!=171 or len(observations)!=171 or sum(r['rawComparison']=='mismatched' for r in rows)!=25:
        raise ValueError('raw identity or failure accounting changed')
    output={'auditStatus':'observations-accounted','rawVerdict':'failed','rawExitCode':1,'rawIssues':25,
            'observations':171,'rawMatched':146,'rawMismatched':25,'eventEvidence':event_report,'rows':rows}
    args.output.write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps({k:v for k,v in output.items() if k not in ['rows','eventEvidence']},indent=2))
if __name__=='__main__':
    try:main()
    except (OSError,ValueError,TypeError,KeyError,SyntaxError) as error:
        print('quoted raw audit failed: '+str(error),file=sys.stderr);sys.exit(1)
