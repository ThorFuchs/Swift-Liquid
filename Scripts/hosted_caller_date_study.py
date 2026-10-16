#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Prespecified release/caller/date hypotheses. Never merged as a production workflow."""
import hashlib,json,os,platform,shlex,shutil,statistics,sys,tempfile
from pathlib import Path
from compare_benchmarks import (ROOT,OUTPUT,ENV,COMMANDS,HARNESS,HARNESS_SHA256,MANIFEST_SHA256,run,git,extract,library_hash,index_records,comparisons,distribution)
MERGED='e29ec2a639b8d73a1c885b541f1bcef408c9c2a7'
CANDIDATE='5d1223608cd1b31e185acce76d3d659a316bb038'
MERGED_HASH='6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a'
CANDIDATE_HASH='77b6ec497a99005c01a34a370ac727089b62a685c1a62f722e0337f8e0db7d55'
VERSIONS={'v130':'9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e','v131':'fb81cf4ff01f1bf098ceb5fff65638b1271294e0','mergedA':MERGED,'candidate':CANDIDATE,'mergedB':MERGED}
TEST_PORT=['Tests/LiquidTests/DateFormattingTests.swift','Tests/TestInventory.json','Documentation/Testing.md']

def index_probe(result):
    assert result['configuration']=='release' and result['caller'] in ['actor','concurrent']
    rows=result['records']; assert len(rows)==6
    indexed={r['name']:r for r in rows}
    assert set(indexed)=={'empty-async','checked-async','interpolation','interpolation-metrics','date','date-metrics'}
    for name,r in indexed.items():
        assert (r['samples'],r['warmupSamples'],r['repetitionsPerSample'])==(25,10,100)
        times=r['sampleNanoseconds']; assert len(times)==25 and all(0<t<float('inf') for t in times)
        ordered=sorted(times)
        assert (r['medianNanoseconds'],r['p95Nanoseconds'],r['minimumNanoseconds'],r['maximumNanoseconds'])==(ordered[12],ordered[23],ordered[0],ordered[-1])
        expected='2024-02-03 04:05:06 +05:30 123456789' if name.startswith('date') else 'Hello, Swift!'
        checksum=14695981039346656037
        for _ in range(3500):
            for byte in expected.encode(): checksum=((checksum^byte)*1099511628211)&((1<<64)-1)
        assert r['outputBytes']==len(expected.encode()) and r['fnv1aChecksum']==format(checksum,'x')
    return indexed

def main():
    assert ENV.get('LIQUID_RUNNER_ENVIRONMENT')=='github-hosted'
    harness=git('show',VERSIONS['v130']+':'+HARNESS)
    manifest=git('show',VERSIONS['v130']+':Tools/Benchmarks/Package.swift')
    assert hashlib.sha256(harness).hexdigest()==HARNESS_SHA256
    assert hashlib.sha256(manifest).hexdigest()==MANIFEST_SHA256
    marker='    static func main() async throws {\n'; assert harness.decode().count(marker)==1
    generic=harness.decode().replace(marker,'    static func main() async throws { try await runOnGenericExecutor() }\n\n    @concurrent\n    private static func runOnGenericExecutor() async throws {\n').encode()
    generic_manifest=manifest.replace(b'"LiquidBenchmarks"',b'"LiquidGenericBenchmarks"')
    probe=(ROOT/'Tools/CallerStudy/CallerProbe.swift').read_bytes()
    for n,b in [('generic-harness.swift',generic),('generic-manifest.swift',generic_manifest),('CallerProbe.swift',probe)]: (OUTPUT/n).write_bytes(b)
    metadata={'operation':'remaining-caller-date-investigation','mergedCommit':MERGED,'candidateCommit':CANDIDATE,'versions':VERSIONS,'harnessSHA256':HARNESS_SHA256,'manifestSHA256':MANIFEST_SHA256,'genericHarnessSHA256':hashlib.sha256(generic).hexdigest(),'genericManifestSHA256':hashlib.sha256(generic_manifest).hexdigest(),'probeSHA256':hashlib.sha256(probe).hexdigest(),'commands':COMMANDS,'phases':{},'qualifications':{},'sourceManifests':{},'librarySHA256':{},'checkpointCounts':{},'probeRuns':[], 'workflowCommit':ENV.get('GITHUB_SHA'),'runnerEnvironment':ENV.get('LIQUID_RUNNER_ENVIRONMENT'),'toolchain':run(['xcrun','swift','--version'],'toolchain'),'platform':platform.platform(),'logicalCPUs':os.cpu_count()}
    metadata['hardware']={k:run(['sysctl','-n',k],'host-'+k.replace('.','-')) for k in ['hw.model','hw.physicalcpu','hw.memsize','machdep.cpu.brand_string']}
    with tempfile.TemporaryDirectory(prefix='liquid-caller-date-') as temp:
        for label,commit in [('baseline-test-port',MERGED),('candidate',CANDIDATE)]:
            q=Path(temp)/('qualification-'+label)/'Swift-Liquid';q.parent.mkdir()
            run(['git','worktree','add','--detach',str(q),commit],label+'-checkout')
            if label=='baseline-test-port':
                for name in TEST_PORT:(q/name).write_bytes(git('show',CANDIDATE+':'+name))
            assert library_hash(q)==(MERGED_HASH if label=='baseline-test-port' else CANDIDATE_HASH)
            try:run([sys.executable,'-B','Scripts/ci.py','--lane','development'],label+'-development',cwd=q)
            finally:
                if (q/'Artifacts/development').exists():shutil.copytree(q/'Artifacts/development',OUTPUT/(label+'-development'))
            receipt=json.loads((OUTPUT/(label+'-development/receipt.json')).read_text());assert receipt['status']=='passed'
            assert receipt['testLanes'][0]['testFunctions']==81 and receipt['testLanes'][0]['completedCases']==2178
            metadata['qualifications'][label]={'sourceCommit':commit,'testPort':TEST_PORT if label=='baseline-test-port' else [],'receipt':label+'-development/receipt.json'}
            run(['git','worktree','remove','--force',str(q)],label+'-cleanup')
        binaries={}; flags=shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS',''))
        for label,commit in VERSIONS.items():
            root=Path(temp)/label/'Swift-Liquid';root.mkdir(parents=True);extract(commit,root)
            digest=library_hash(root);metadata['librarySHA256'][label]=digest
            metadata['sourceManifests'][label]=[{'path':str(p.relative_to(root)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted((root/'Sources/Liquid').rglob('*.swift'))]
            metadata['checkpointCounts'][label]=sum(p.read_text().count('Task.checkCancellation()') for p in (root/'Sources/Liquid').rglob('*.swift'))
            if label=='candidate':
                assert digest==CANDIDATE_HASH
                assert git('diff',MERGED,CANDIDATE,'--name-only','--','Sources/Liquid').decode().splitlines()==['Sources/Liquid/Support/DateFormatting.swift']
                assert (root/'Sources/Liquid/LiquidLimits.swift').read_bytes()==git('show',MERGED+':Sources/Liquid/LiquidLimits.swift')
                (OUTPUT/'candidate-core.diff').write_bytes(git('diff',MERGED,CANDIDATE,'--','Sources/Liquid'))
            (root/HARNESS).write_bytes(harness);(root/'Tools/Benchmarks/Package.swift').write_bytes(manifest)
            package=root/'Tools/GenericBenchmarks';(package/'Sources/LiquidGenericBenchmarks').mkdir(parents=True)
            (package/'Package.swift').write_bytes(generic_manifest);(package/'Sources/LiquidGenericBenchmarks/main.swift').write_bytes(generic)
            for driver,pkg,product in [('common',root/'Tools/Benchmarks','LiquidBenchmarks'),('concurrent',package,'LiquidGenericBenchmarks')]:
                run(['xcrun','swift','build','-c','release','--package-path',str(pkg),*flags],label+'-'+driver+'-build')
                loc=run(['xcrun','swift','build','-c','release','--package-path',str(pkg),'--show-bin-path',*flags],label+'-'+driver+'-binary')
                binaries[label,driver]=str(Path(loc.splitlines()[-1])/product)
            if label=='mergedA':
                pkg=root/'Tools/CallerProbe';(pkg/'Sources/LiquidCallerProbe').mkdir(parents=True)
                (pkg/'Package.swift').write_bytes(manifest.replace(b'"LiquidBenchmarks"',b'"LiquidCallerProbe"'))
                (pkg/'Sources/LiquidCallerProbe/main.swift').write_bytes(probe)
                run(['xcrun','swift','build','-c','release','--package-path',str(pkg),*flags],'probe-build')
                loc=run(['xcrun','swift','build','-c','release','--package-path',str(pkg),'--show-bin-path',*flags],'probe-binary').splitlines()[-1]
                binaries['probe']=str(Path(loc)/'LiquidCallerProbe')
                run(['xcrun','swiftc','-O','-swift-version','6','-parse-as-library','-emit-sil','-I',str(Path(loc)/'Modules'),str(pkg/'Sources/LiquidCallerProbe/main.swift')],'probe-optimized-sil')
            if label in ['mergedA','candidate']:
                run(['xcrun','nm','-n',binaries[label,'common']],label+'-symbols')
                run(['xcrun','otool','-tvV',binaries[label,'common']],label+'-assembly')
        assert metadata['librarySHA256']['mergedA']==metadata['librarySHA256']['mergedB']==MERGED_HASH
        assert metadata['checkpointCounts']['mergedA']==metadata['checkpointCounts']['candidate']==metadata['checkpointCounts']['mergedB']
        metadata['allBinariesBuiltBeforeTiming']=True
        for block in range(1,4):
            for phase_name,labels in [('release',['v130','v131']),('merged',['v131','mergedA']),('formatter',['mergedA','candidate']),('identical',['mergedA','mergedB'])]:
                for driver in ['common','concurrent']:
                    key=phase_name+'-'+driver;phase=metadata['phases'].setdefault(key,{'labels':labels,'driver':driver,'runs':[]})
                    for position,label in enumerate([labels[0],labels[1],labels[1],labels[0]]):
                        name=f'{key}-{block}-{position+1}-{label}';dst=OUTPUT/(name+'.json');before=os.getloadavg()
                        run([binaries[label,driver],str(dst)],name);index_records(json.loads(dst.read_text()))
                        phase['runs'].append({'name':name,'version':label,'block':block,'result':dst.name,'loadAverageBefore':before,'loadAverageAfter':os.getloadavg()})
            for position,caller in enumerate(['actor','concurrent','concurrent','actor']):
                name=f'probe-{block}-{position+1}-{caller}';dst=OUTPUT/(name+'.json');before=os.getloadavg()
                run([binaries['probe'],caller,str(dst)],name);index_probe(json.loads(dst.read_text()))
                metadata['probeRuns'].append({'name':name,'caller':caller,'block':block,'result':dst.name,'loadAverageBefore':before,'loadAverageAfter':os.getloadavg()})
    for phase in metadata['phases'].values():
        records={r['name']:index_records(json.loads((OUTPUT/r['result']).read_text())) for r in phase['runs']}
        phase['comparisons']=comparisons(phase['runs'],records,phase['labels'])
        phase['reviewRequired']=[r['name']+'/'+r['mode'] for r in phase['comparisons'] if r['requiresReview']]
        phase['varianceReviewRequired']=[r['name']+'/'+r['mode'] for r in phase['comparisons'] if r['varianceRequiresReview']]
        for row in phase['comparisons']:
            key=row['name'],row['mode'];row['blockChangesPercent']=[]
            for block in range(1,4):
                values={l:[records[r['name']][key]['medianNanoseconds'] for r in phase['runs'] if r['block']==block and r['version']==l] for l in phase['labels']}
                row['blockChangesPercent'].append((statistics.median(values[phase['labels'][1]])/statistics.median(values[phase['labels'][0]])-1)*100)
    metadata['probeDistributions']={}
    for kind in ['empty-async','checked-async','interpolation','interpolation-metrics','date','date-metrics']:
        metadata['probeDistributions'][kind]={caller:distribution([index_probe(json.loads((OUTPUT/r['result']).read_text()))[kind]['medianNanoseconds'] for r in metadata['probeRuns'] if r['caller']==caller]) for caller in ['actor','concurrent']}
    metadata['status']='measured'
    (OUTPUT/'caller-date-study.json').write_text(json.dumps(metadata,indent=2)+'\n')
    print(json.dumps({'status':'measured','phases':{k:{'medianFlags':len(p['reviewRequired']),'spreadFlags':len(p['varianceReviewRequired'])} for k,p in metadata['phases'].items()}},indent=2))

if __name__=='__main__':main()
