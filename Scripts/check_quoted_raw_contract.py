#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify raw observation audit rejects missing, altered and operational cases."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--log',type=Path,required=True);p.add_argument('--events',type=Path,required=True);a=p.parse_args()
 lines=a.log.read_text().splitlines();events=a.events.read_text().splitlines()
 def index(prefix):
  found=[i for i,line in enumerate(lines) if line.startswith(prefix)]
  if len(found)!=1:raise ValueError('missing or duplicated control observation: '+prefix)
  return found[0]
 deferred=index('RECOVERY lax single_escaped_closer ')
 framing=index('RECOVERY lax adjacent_output_delimiter ')
 results=[]
 for name in ['unchanged','missing','duplicate','operational','wrong_output','known_issue']:
  with tempfile.TemporaryDirectory(prefix='quote-raw-contract-') as tmp:
   d=Path(tmp);test_lines=list(lines);test_events=list(events)
   if name=='missing':test_lines.pop(deferred)
   elif name=='duplicate':test_lines.append(test_lines[deferred])
   elif name=='operational':test_lines[deferred]='RECOVERY lax single_escaped_closer operational-error cancelled'
   elif name=='wrong_output':test_lines[framing]='RECOVERY lax adjacent_output_delimiter output=[0]'
   elif name=='known_issue':
    for i,line in enumerate(test_events):
     row=json.loads(line); payload=row.get('payload',{})
     if row.get('kind')=='event' and payload.get('kind')=='issueRecorded':
      payload['issue']['isKnown']=True;test_events[i]=json.dumps(row);break
    else:raise ValueError('raw stream has no issue')
   (d/'raw.log').write_text('\n'.join(test_lines)+'\n');(d/'raw.events').write_text('\n'.join(test_events)+'\n')
   result=subprocess.run([sys.executable,'-B',str(ROOT/'Scripts/check_quoted_raw_observations.py'),'--log',str(d/'raw.log'),'--events',str(d/'raw.events'),'--output',str(d/'audit.json')],capture_output=True,text=True)
   if (result.returncode==0)!=(name=='unchanged'):raise ValueError('raw negative control failed: '+name+' '+result.stderr)
   results.append({'name':name,'exitCode':result.returncode})
 print(json.dumps({'status':'negative-controls-passed','cases':results},indent=2))
if __name__=='__main__':
 try:main()
 except (OSError,ValueError,KeyError,TypeError) as error:print(str(error),file=sys.stderr);sys.exit(1)
