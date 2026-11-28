#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Negative probes for the reviewed quote policy validator."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
FILES=['Scripts/check_quoted_literal_review.py','Tests/LiquidTests/Fixtures/QuotedStringReferenceCases.json',
       'Tests/LiquidTests/Fixtures/LaxQuoteRecoveryCases.json','Tests/LiquidTests/Fixtures/SL21-02A4-ReviewedPolicy.json',
       'Documentation/ControlTower/SL21-02A3-DISPOSITIONS.json',
       'Tests/LiquidTests/QuotedStringCompatibilityTests.swift','Tests/LiquidTests/LaxQuoteRecoveryReferenceTests.swift',
       'Tools/QuotedStringRawTests/Tests/QuotedStringRawTests/QuotedStringCompatibilityTests.swift',
       'Tools/QuotedStringRawTests/Tests/QuotedStringRawTests/LaxQuoteRecoveryReferenceTests.swift',
       'Tools/QuotedStringRawTests/Tests/QuotedStringRawTests/Fixtures/QuotedStringReferenceCases.json',
       'Tools/QuotedStringRawTests/Tests/QuotedStringRawTests/Fixtures/LaxQuoteRecoveryCases.json']
class PolicyContract(unittest.TestCase):
    def test_fail_closed(self):
        for name in ['unchanged','unknown_identity','source_change','reference_change','incorrect_output','operational_error','duplicate_json','raw_assertion_change','fixture_change']:
            with self.subTest(name=name), tempfile.TemporaryDirectory(prefix='quote-policy-') as tmp:
                root=Path(tmp)
                for entry in FILES:
                    dst=root/entry;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/entry,dst)
                script=root/FILES[0]; policy=root/FILES[3]
                if name not in ['unchanged','raw_assertion_change','fixture_change']:
                    data=json.loads(policy.read_text())
                    if name=='unknown_identity':data['rows'][0]['id']='lax/unknown'
                    if name=='source_change':data['rows'][0]['sourceBytes'][0]=0
                    if name=='reference_change':data['rows'][0]['reference']['outcome']='parse-error'
                    if name=='incorrect_output':next(r for r in data['rows'] if r['disposition']=='APPROVED_INERT_FRAMING')['swift']['outputBytes']=[0]
                    if name=='operational_error':data['rows'][0]['swift']['outcome']='limit-exceeded'
                    body=json.dumps(data,indent=2)+'\n'
                    if name=='duplicate_json':body=body.replace('  "schemaVersion": 1,','  "schemaVersion": 1,\n  "schemaVersion": 1,',1)
                    policy.write_text(body)
                    # Permit the modified digest to reach semantic validation.
                    code=script.read_text();old='1352e4b864c1455c41bb665f45bbe921c18d2fa16a7e4bf9b0c8ccd80773705f';new=hashlib.sha256(policy.read_bytes()).hexdigest();assert old in code;script.write_text(code.replace(old,new))
                elif name=='raw_assertion_change':
                    target=root/FILES[7];target.write_text(target.read_text()+'\n// changed raw assertion copy\n')
                elif name=='fixture_change':
                    target=root/FILES[1];target.write_bytes(target.read_bytes()+b' ')
                run=subprocess.run([sys.executable,'-B',str(script)],capture_output=True,text=True)
                if name=='unchanged':self.assertEqual(run.returncode,0,run.stderr)
                else:self.assertNotEqual(run.returncode,0,run.stdout)
if __name__=='__main__':unittest.main()
