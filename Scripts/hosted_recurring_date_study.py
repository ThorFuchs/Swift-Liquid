#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Prespecified wall/CPU follow-up; diagnostic branch only."""
import hashlib,json,os,platform,shlex,shutil,statistics,sys,tempfile
from pathlib import Path
from compare_benchmarks import ROOT,OUTPUT,ENV,COMMANDS,HARNESS,HARNESS_SHA256,MANIFEST_SHA256,run,git,extract,library_hash,index_records,comparisons,distribution
MAIN='e5291b040c046415f4b535903d23f56c49320c0e'
VERSIONS={'v130':'9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e','mainA':MAIN,'mainB':MAIN}
CORE='6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a'
SOURCES={'iso':("{{ stamp | date: '%F %T %:z %N' }}","2024-02-03 04:05:06 +05:30 123456789"),'epoch':("{{ stamp | date: '%F %T %:z %N' }}","1970-01-01 00:00:00 +00:00 000000000"),'filter':("{{ title | strip | upcase | escape }}","&lt;SWIFT&gt;")}
MODES=['parse','source','reused','source-metrics','reused-metrics']
def index_cpu(result,caller):
    assert result['configuration']=='release' and result['caller']==caller
    rows=result['records'];assert len(rows)==15
    records={(r['name'],r['mode']):r for r in rows};assert set(records)=={(n,m) for n in SOURCES for m in MODES}
    for (name,mode),r in records.items():
        assert (r['samples'],r['warmupSamples'],r['repetitionsPerSample'])==(25,10,100)
        payload=SOURCES[name][0 if mode=='parse' else 1].encode();h=14695981039346656037
        for _ in range(3500):
            for b in payload:h=((h^b)*1099511628211)&((1<<64)-1)
        assert (r['outputBytes'],r['fnv1aChecksum'])==(len(payload),format(h,'x'))
        for clock in ['wall','cpu']:
            times=r[clock+'SampleNanoseconds'];assert len(times)==25 and all(0<t<float('inf') for t in times)
            ordered=sorted(times);assert r[clock+'MedianNanoseconds']==ordered[12] and r[clock+'P95Nanoseconds']==ordered[23]
    return records

def main():
    assert ENV.get('LIQUID_RUNNER_ENVIRONMENT')=='github-hosted'
    harness=git('show',VERSIONS['v130']+':'+HARNESS);manifest=git('show',VERSIONS['v130']+':Tools/Benchmarks/Package.swift')
    assert hashlib.sha256(harness).hexdigest()==HARNESS_SHA256 and hashlib.sha256(manifest).hexdigest()==MANIFEST_SHA256
    probe=(ROOT/'Tools/DateCPUStudy/DateCPUProbe.swift').read_bytes()
    meta={'operation':'recurring-date-wall-cpu','versions':VERSIONS,'workflowCommit':ENV.get('GITHUB_SHA'),'runnerEnvironment':ENV['LIQUID_RUNNER_ENVIRONMENT'],'commands':COMMANDS,'phases':{},'sourceManifests':{},'librarySHA256':{},'probeSHA256':hashlib.sha256(probe).hexdigest(),'harnessSHA256':HARNESS_SHA256,'manifestSHA256':MANIFEST_SHA256,'toolchain':run(['xcrun','swift','--version'],'toolchain'),'platform':platform.platform(),'logicalCPUs':os.cpu_count()}
    meta['hardware']={k:run(['sysctl','-n',k],'host-'+k.replace('.','-')) for k in ['hw.model','hw.physicalcpu','hw.memsize','machdep.cpu.brand_string']}
    (OUTPUT/'DateCPUProbe.swift').write_bytes(probe)
    with tempfile.TemporaryDirectory(prefix='liquid-recurring-date-') as temp:
        q=Path(temp)/'qualification/Swift-Liquid';q.parent.mkdir()
        run(['git','worktree','add','--detach',str(q),MAIN],'qualification-checkout')
        try:run([sys.executable,'-B','Scripts/ci.py','--lane','development'],'qualification-development',cwd=q)
        finally:
            if (q/'Artifacts/development').exists():shutil.copytree(q/'Artifacts/development',OUTPUT/'qualification-development')
        receipt=json.loads((OUTPUT/'qualification-development/receipt.json').read_text());assert receipt['status']=='passed'
        assert (receipt['testLanes'][0]['testFunctions'],receipt['testLanes'][0]['completedCases'])==(81,2178)
        run(['git','worktree','remove','--force',str(q)],'qualification-cleanup')
        binaries={};flags=shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS',''))
        for label,commit in VERSIONS.items():
            root=Path(temp)/label/'Swift-Liquid';root.mkdir(parents=True);extract(commit,root)
            meta['librarySHA256'][label]=library_hash(root)
            if label.startswith('main'):assert meta['librarySHA256'][label]==CORE
            meta['sourceManifests'][label]=[{'path':str(p.relative_to(root)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted((root/'Sources/Liquid').rglob('*.swift'))]
            (root/HARNESS).write_bytes(harness);(root/'Tools/Benchmarks/Package.swift').write_bytes(manifest)
            pkg=root/'Tools/DateCPUProbe';(pkg/'Sources/DateCPUProbe').mkdir(parents=True)
            (pkg/'Package.swift').write_bytes(manifest.replace(b'"LiquidBenchmarks"',b'"DateCPUProbe"'));(pkg/'Sources/DateCPUProbe/main.swift').write_bytes(probe)
            for driver,package,product in [('common',root/'Tools/Benchmarks','LiquidBenchmarks'),('probe',pkg,'DateCPUProbe')]:
                run(['xcrun','swift','build','-c','release','--package-path',str(package),*flags],label+'-'+driver+'-build')
                loc=run(['xcrun','swift','build','-c','release','--package-path',str(package),'--show-bin-path',*flags],label+'-'+driver+'-binary').splitlines()[-1]
                binaries[label,driver]=str(Path(loc)/product)
        meta['allSixBinariesBuiltBeforeTiming']=True
        for block in range(1,4):
            for driver in ['common','actor','concurrent']:
                for phase,labels in [('release',['v130','mainA']),('identical',['mainA','mainB'])]:
                    key=phase+'-'+driver;p=meta['phases'].setdefault(key,{'labels':labels,'driver':driver,'runs':[]})
                    for position,label in enumerate([labels[0],labels[1],labels[1],labels[0]]):
                        name=f'{key}-{block}-{position+1}-{label}';dst=OUTPUT/(name+'.json');load=os.getloadavg()
                        cmd=[binaries[label,'common'],str(dst)] if driver=='common' else [binaries[label,'probe'],driver,str(dst)]
                        run(cmd,name);data=json.loads(dst.read_text())
                        if driver=='common':index_records(data)
                        else:index_cpu(data,driver)
                        p['runs'].append({'name':name,'version':label,'block':block,'result':dst.name,'loadAverageBefore':load,'loadAverageAfter':os.getloadavg()})
    for p in meta['phases'].values():
        labels=p['labels'];raw={r['name']:(index_records(json.loads((OUTPUT/r['result']).read_text())) if p['driver']=='common' else index_cpu(json.loads((OUTPUT/r['result']).read_text()),p['driver'])) for r in p['runs']}
        indexed={}
        for name,rows in raw.items():
            if p['driver']=='common':indexed[name]=rows
            else:
                indexed[name]={(n,m+'-'+c):{'name':n,'mode':m+'-'+c,'medianNanoseconds':r[c+'MedianNanoseconds'],**{k:r[k] for k in ['outputBytes','fnv1aChecksum','samples','warmupSamples','repetitionsPerSample']}} for (n,m),r in rows.items() for c in ['wall','cpu']}
        p['comparisons']=comparisons(p['runs'],indexed,labels)
        p['reviewRequired']=[r['name']+'/'+r['mode'] for r in p['comparisons'] if r['requiresReview']]
        p['varianceReviewRequired']=[r['name']+'/'+r['mode'] for r in p['comparisons'] if r['varianceRequiresReview']]
        for row in p['comparisons']:
            key=row['name'],row['mode'];row['blockChangesPercent']=[]
            for block in range(1,4):
                vals={l:[indexed[r['name']][key]['medianNanoseconds'] for r in p['runs'] if r['block']==block and r['version']==l] for l in labels}
                row['blockChangesPercent'].append((statistics.median(vals[labels[1]])/statistics.median(vals[labels[0]])-1)*100)
    meta['status']='measured';(OUTPUT/'recurring-date-study.json').write_text(json.dumps(meta,indent=2)+'\n')
    print(json.dumps({'status':'measured','phases':{k:{'medianFlags':len(p['reviewRequired']),'spreadFlags':len(p['varianceReviewRequired'])} for k,p in meta['phases'].items()}}))
if __name__=='__main__':main()
