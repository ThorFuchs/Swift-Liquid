#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""One-off matched checkpoint ablation and identical-source control, not a release gate."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import statistics
import tempfile
from compare_benchmarks import (ROOT, OUTPUT, ENV, COMMANDS, HARNESS, HARNESS_SHA256, MANIFEST_SHA256,
    run, git, extract, library_hash, index_records, comparisons)

SOURCE='8a9b65fc05298073014140cd9117f90eebaa032e'
EXPECTED='50b372f97e4f3429647723b7c9ec8c4b8cca13759774fa069b369109b48fafa4'
BASE='9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e'

def main():
    harness=git('show',BASE+':'+HARNESS)
    manifest=git('show',BASE+':Tools/Benchmarks/Package.swift')
    assert hashlib.sha256(harness).hexdigest()==HARNESS_SHA256
    assert hashlib.sha256(manifest).hexdigest()==MANIFEST_SHA256
    metadata={'operation':'supplementary-hosted-checkpoint-control','sourceCommit':SOURCE,'expectedLibrarySHA256':EXPECTED,
        'harnessSHA256':HARNESS_SHA256,'manifestSHA256':MANIFEST_SHA256,'toolchain':run(['xcrun','swift','--version'],'toolchain'),
        'platform':platform.platform(),'logicalCPUs':os.cpu_count(),'runnerEnvironment':ENV.get('LIQUID_RUNNER_ENVIRONMENT'),
        'commands':COMMANDS,'phases':{'ablation':{'runs':[]},'identical':{'runs':[]}}}
    assert metadata['runnerEnvironment']=='github-hosted'
    metadata['hardware']={key:run(['sysctl','-n',key],'host-'+key.replace('.','-')) for key in ['hw.model','hw.physicalcpu','hw.memsize','machdep.cpu.brand_string']}
    with tempfile.TemporaryDirectory(prefix='liquid-hosted-control-') as tmp:
        binaries={};hashes={}
        for name in ['control','checkpointA','checkpointB']:
            root=Path(tmp)/name/'Swift-Liquid';root.mkdir(parents=True);extract(SOURCE,root)
            assert library_hash(root)==EXPECTED
            if name=='control':
                p=root/'Sources/Liquid/LiquidLimits.swift';before=p.read_text()
                check='// Final synchronous work can finish after the last evaluator checkpoint.\n        try Task.checkCancellation()\n'
                assert before.count(check)==1
                after=before.replace(check,'// Uncancelled performance control: checkpoint omitted.\n')
                p.write_text(after)
                (OUTPUT/'control.diff').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='checkpoint/LiquidLimits.swift',tofile='control/LiquidLimits.swift')))
            hashes[name]=library_hash(root)
            (root/HARNESS).write_bytes(harness);(root/'Tools/Benchmarks/Package.swift').write_bytes(manifest)
            package=str(root/'Tools/Benchmarks'); flags=shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS',''))
            run(['xcrun','swift','build','-c','release','--package-path',package,*flags],name+'-build')
            location=run(['xcrun','swift','build','-c','release','--package-path',package,'--show-bin-path',*flags],name+'-binary')
            binaries[name]=str(Path(location.splitlines()[-1])/'LiquidBenchmarks')
        assert hashes['checkpointA']==hashes['checkpointB']==EXPECTED and hashes['control']!=EXPECTED
        metadata['librarySHA256']=hashes
        for block in range(3):
            for phase,order in [('ablation',['control','checkpointA','checkpointA','control']),('identical',['checkpointA','checkpointB','checkpointB','checkpointA'])]:
                for position,label in enumerate(order):
                    name=f'{phase}-{block+1}-{position+1}-{label}';dest=OUTPUT/(name+'.json');before=os.getloadavg()
                    run([binaries[label],str(dest)],name);index_records(json.loads(dest.read_text()))
                    metadata['phases'][phase]['runs'].append({'name':name,'version':label,'result':dest.name,'block':block+1,'loadAverageBefore':before,'loadAverageAfter':os.getloadavg()})
    for name,labels in [('ablation',['control','checkpointA']),('identical',['checkpointA','checkpointB'])]:
        phase=metadata['phases'][name];records={r['name']:index_records(json.loads((OUTPUT/r['result']).read_text())) for r in phase['runs']}
        phase['comparisons']=comparisons(phase['runs'],records,labels)
        phase['reviewRequired']=[r['name']+'/'+r['mode'] for r in phase['comparisons'] if r['requiresReview']]
        phase['varianceReviewRequired']=[r['name']+'/'+r['mode'] for r in phase['comparisons'] if r['varianceRequiresReview']]
        for row in phase['comparisons']:
            key=(row['name'],row['mode']);effects=[]
            for block in range(1,4):
                values={label:[records[r['name']][key]['medianNanoseconds'] for r in phase['runs'] if r['block']==block and r['version']==label] for label in labels}
                effects.append((statistics.median(values[labels[1]])/statistics.median(values[labels[0]])-1)*100)
            row['blockChangesPercent']=effects
    metadata['status']='measured';(OUTPUT/'checkpoint-control.json').write_text(json.dumps(metadata,indent=2)+'\n')
    print(json.dumps({name:{'flags':phase['reviewRequired'],'spreadFlags':phase['varianceReviewRequired']} for name,phase in metadata['phases'].items()},indent=2))

if __name__=='__main__':main()
