#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Frozen staged date CPU/executor investigation, diagnostic branch only."""
import datetime,hashlib,json,os,platform,shlex,shutil,statistics,sys,tarfile,tempfile,traceback
from pathlib import Path
from xml.etree import ElementTree as ET
import compare_benchmarks as cb
from date_trace_benchmark_index import index_cpu,SOURCES,MODES
from trace_analysis import intervals,cpu,executors
ROOT=cb.ROOT;OUT=cb.OUTPUT;ENV=cb.ENV
BASE='9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e'
MAIN='1313f82ac03b6f51224d6c4219fc26ad0a598ddf'
CORE='6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a'
VERSIONS={'v130':BASE,'mainA':MAIN,'mainB':MAIN}
STATE=OUT/'trace-study-state.json'
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def run(cmd,name,**kwargs):
    print(name,flush=True)
    return cb.run(cmd,name,**kwargs)
def save(m):STATE.write_text(json.dumps(m,indent=2)+'\n')
def load():
    m=json.loads(STATE.read_text());cb.COMMANDS[:]=m['commands'];m['commands']=cb.COMMANDS;return m

def build(m):
    assert ENV.get('LIQUID_RUNNER_ENVIRONMENT')=='github-hosted'
    m.update({'versions':VERSIONS,'workflowCommit':ENV.get('GITHUB_SHA'),'runnerEnvironment':ENV['LIQUID_RUNNER_ENVIRONMENT'],'toolchain':run(['xcrun','swift','--version'],'toolchain'),'platform':platform.platform(),'logicalCPUs':os.cpu_count(),'sourceManifests':{},'librarySHA256':{},'binaries':{},'phases':{},'traces':[]})
    m['hardware']={k:run(['sysctl','-n',k],'host-'+k.replace('.','-')) for k in ['hw.model','hw.physicalcpu','hw.memsize','machdep.cpu.brand_string']}
    for cmd,name in [(['xcrun','xctrace','list','templates'],'templates'),(['xcrun','xctrace','list','instruments'],'instruments'),(['xcrun','xctrace','help','record'],'record-help'),(['xcrun','xctrace','help','export'],'export-help'),(['xcrun','xctrace','help','symbolicate'],'symbolicate-help')]:run(cmd,name)
    assert 'Swift Concurrency' in (OUT/'templates.log').read_text() and 'Time Profiler' in (OUT/'templates.log').read_text()
    assert all(n in (OUT/'instruments.log').read_text() for n in ['Swift Executors','Swift Tasks','Points of Interest'])
    for template in ['Time Profiler','Swift Concurrency']:
        raw=run(['xcrun','xctrace','record','--template',template,'--show-recording-options'],template.replace(' ','-')+'-options')
        assert 'Points of Interest' in json.loads(raw) and 'Time Profiler' in json.loads(raw)
    temp=Path(tempfile.mkdtemp(prefix='liquid-date-trace-',dir=ENV.get('RUNNER_TEMP')));m['scratch']=str(temp)
    m['initialFreeDiskBytes']=shutil.disk_usage(temp).free;assert m['initialFreeDiskBytes']>=6*1024**3
    capabilitySource=ROOT/'Tools/DateTraceStudy/HostedTraceCapability.swift'
    capabilityBinary=temp/'BoundedCapability'
    run(['xcrun','swiftc','-swift-version','6','-parse-as-library','-O','-g',str(capabilitySource),'-o',str(capabilityBinary)],'capability-build')
    cap=OUT/'capability.trace';capout=OUT/'capability-output.log'
    run(['xcrun','xctrace','record','--template','Swift Concurrency','--output',str(cap),'--no-prompt','--time-limit','30s','--target-stdout',str(capout),'--launch','--',str(capabilityBinary)],'capability-record')
    text=(OUT/'capability-record.log').read_text()+capout.read_text()
    assert 'Target app exited' in text and 'Capability result verified: 100' in text and 'Reached specified time limit' not in text
    assert not any(x in text.lower() for x in ['quarantined','events were dropped','data was lost','buffer overflow'])
    for schema in ['SwiftTaskStateTable','OSSignpostIntervals','time-profile']:
        run(['xcrun','xctrace','export','--input',str(cap),'--xpath','/trace-toc/run[@number="1"]/data/table[@schema="'+schema+'"]','--output',str(OUT/('capability-'+schema+'.xml'))],'capability-'+schema)
    from trace_analysis import Table
    sp=Table(OUT/'capability-OSSignpostIntervals.xml');region=next(r for r in sp.rows if sp.text(r['name'])=='CapabilityBatch')
    low=sp.number(region['start']);scope={'capability':{'start':low,'end':low+sp.number(region['duration'])}};pid=sp.pid(region['process'])
    analysis=executors(OUT/'capability-SwiftTaskStateTable.xml',scope,pid)
    assert analysis['capability']['executorRunningIntervals']['Global Concurrent Executor']==100
    assert analysis['capability']['observedRunningSegmentTransitions']['Main Actor -> Global Concurrent Executor']==100
    assert analysis['capability']['observedRunningSegmentTransitions']['Global Concurrent Executor -> Main Actor']==100
    cpuAnalysis=cpu(OUT/'capability-time-profile.xml',scope,pid)
    m['captureCapability']={'scope':'Standalone100calls, no engine data','executor':analysis,'cpu':cpuAnalysis}
    with tarfile.open(OUT/'capability.trace.tar.gz','w:gz') as archive:archive.add(cap,arcname='capability.trace')
    shutil.rmtree(cap)
    q=temp/'qualification/Swift-Liquid';q.parent.mkdir()
    run(['git','worktree','add','--detach',str(q),MAIN],'qualification-checkout')
    try:run([sys.executable,'-B','Scripts/ci.py','--lane','development'],'qualification-development',cwd=q)
    finally:
        if (q/'Artifacts/development').exists():shutil.copytree(q/'Artifacts/development',OUT/'qualification-development')
    receipt=json.loads((OUT/'qualification-development/receipt.json').read_text());assert receipt['status']=='passed'
    assert (receipt['testLanes'][0]['testFunctions'],receipt['testLanes'][0]['completedCases'])==(81,2178)
    run(['git','worktree','remove','--force',str(q)],'qualification-cleanup')
    harness=cb.git('show',BASE+':'+cb.HARNESS);manifest=cb.git('show',BASE+':Tools/Benchmarks/Package.swift')
    assert hashlib.sha256(harness).hexdigest()==cb.HARNESS_SHA256 and hashlib.sha256(manifest).hexdigest()==cb.MANIFEST_SHA256
    flags=[*shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS','')),'-Xswiftc','-g'];m['buildFlags']=flags
    m['harnessSHA256']=cb.HARNESS_SHA256;m['manifestSHA256']=cb.MANIFEST_SHA256
    probes={k:(ROOT/'Tools/DateTraceStudy'/v).read_bytes() for k,v in [('probe','DateCPUProbe.swift'),('trace','DateTraceProbe.swift')]}
    m['probeSHA256']={k:hashlib.sha256(v).hexdigest() for k,v in probes.items()}
    for k,v in probes.items():(OUT/(k+'-source.swift')).write_bytes(v)
    m['debugArtifacts']={}
    for label,commit in VERSIONS.items():
        root=temp/label/'Swift-Liquid';root.mkdir(parents=True);cb.extract(commit,root)
        m['librarySHA256'][label]=cb.library_hash(root)
        if label.startswith('main'):assert m['librarySHA256'][label]==CORE
        m['sourceManifests'][label]=[{'path':str(p.relative_to(root)),'sha256':digest(p)} for p in sorted((root/'Sources/Liquid').rglob('*.swift'))]
        (root/cb.HARNESS).write_bytes(harness);(root/'Tools/Benchmarks/Package.swift').write_bytes(manifest)
        packages={'common':(root/'Tools/Benchmarks','LiquidBenchmarks')}
        for kind,source in probes.items():
            product='LiquidDateCPUProbe' if kind=='probe' else 'LiquidDateTraceProbe';pkg=root/('Tools/'+product)
            (pkg/('Sources/'+product)).mkdir(parents=True);(pkg/'Package.swift').write_bytes(manifest.replace(b'"LiquidBenchmarks"',('"'+product+'"').encode()));(pkg/('Sources/'+product+'/main.swift')).write_bytes(source);packages[kind]=(pkg,product)
        m['binaries'][label]={}
        for driver,(pkg,product) in packages.items():
            run(['xcrun','swift','build','-c','release','--package-path',str(pkg),*flags],label+'-'+driver+'-build')
            loc=run(['xcrun','swift','build','-c','release','--package-path',str(pkg),'--show-bin-path',*flags],label+'-'+driver+'-binary').splitlines()[-1]
            m['binaries'][label][driver]=str(Path(loc)/product)
            if driver=='trace':
                symbols=OUT/'symbols'/label;symbols.mkdir(parents=True)
                binaries={Path(loc)/product,*((p/'Liquid').resolve() for p in (pkg/'.build').rglob('Liquid.framework') if (p/'Liquid').is_file())}
                for binary in sorted(binaries):
                    run(['xcrun','dsymutil',str(binary),'-o',str(symbols/(binary.name+'.dSYM'))],label+'-'+binary.name+'-dsym')
                    shutil.copy2(binary,symbols/binary.name)
                    uuid=run(['xcrun','dwarfdump','--uuid',str(binary)],label+'-'+binary.name+'-uuid')
                    m['debugArtifacts'][label+'/'+binary.name]={'sha256':digest(binary),'UUID':uuid}
        save(m)
    m['allNineBinariesBuiltBeforeTiming']=True

def measure(m):
    assert m['allNineBinariesBuiltBeforeTiming'];binaries=m['binaries']
    for block in range(1,4):
        for driver in ['common','actor','concurrent']:
            for phase,labels in [('release',['v130','mainA']),('identical',['mainA','mainB'])]:
                key=phase+'-'+driver;p=m['phases'].setdefault(key,{'labels':labels,'driver':driver,'runs':[]})
                for pos,label in enumerate([labels[0],labels[1],labels[1],labels[0]]):
                    name=f'{key}-{block}-{pos+1}-{label}';dst=OUT/(name+'.json');before=os.getloadavg()
                    cmd=[binaries[label]['common'],str(dst)] if driver=='common' else [binaries[label]['probe'],driver,str(dst)]
                    run(cmd,name);data=json.loads(dst.read_text())
                    if driver=='common':cb.index_records(data)
                    else:index_cpu(data,driver)
                    p['runs'].append({'name':name,'version':label,'block':block,'result':dst.name,'loadAverageBefore':before,'loadAverageAfter':os.getloadavg()});save(m)
    m['allUntracedRunsBeforeCaptures']=True

def capture(m,kind):
    assert m['allUntracedRunsBeforeCaptures'];binaries=m['binaries']
    for caller in ['actor','concurrent']:
        for phase,labels in [('release',['v130','mainA']),('identical',['mainA','mainB'])]:
            for pos,label in enumerate([labels[0],labels[1],labels[1],labels[0]]):
                name=f'trace-{kind}-{caller}-{phase}-{pos+1}-{label}';folder=OUT/name;folder.mkdir()
                free=shutil.disk_usage(folder).free;assert free>=2*1024**3,(name,'less than 2GiB available before capture')
                trace=folder/'capture.trace';dst=folder/'outputs.json';stdout=folder/'target-stdout.log'
                cmd=['xcrun','xctrace','record','--template','Time Profiler' if kind=='cpu' else 'Swift Concurrency']
                cmd+=['--output',str(trace),'--no-prompt','--time-limit','60s','--target-stdout',str(stdout),'--launch','--',binaries[label]['trace'],caller,kind,str(dst)]
                before=os.getloadavg();run(cmd,name+'-record');recordlog=(OUT/(name+'-record.log')).read_text();targetlog=stdout.read_text()
                assert 'Target app exited' in recordlog and 'Reached specified time limit' not in recordlog
                assert not any(s in (recordlog+targetlog).lower() for s in ['quarantined','events were dropped','data was lost','buffer overflow'])
                assert 'Trace probe complete: '+caller+' '+kind in targetlog
                data=json.loads(dst.read_text());assert data['configuration']=='release' and data['caller']==caller and data['capture']==kind
                count,warmups=(20000,100) if kind=='cpu' else (100,10)
                assert len(data['records'])==6 and {r['name'] for r in data['records']}=={n+'-'+v for n in ['iso','epoch','filter'] for v in ['source','reused']}
                for r in data['records']:
                    assert (r['iterations'],r['warmupIterations'])==(count,warmups)
                    expected=SOURCES[r['name'].split('-')[0]][1].encode();h=14695981039346656037
                    for _ in range(count+warmups):
                        for b in expected:h=((h^b)*1099511628211)&((1<<64)-1)
                    assert (r['outputBytes'],r['fnv1aChecksum'])==(len(expected),format(h,'x'))
                archive=folder/'original.trace.tar.gz'
                with tarfile.open(archive,'w:gz') as t:t.add(trace,arcname='capture.trace')
                run(['xcrun','xctrace','symbolicate','--input',str(trace),'--dsym',str(OUT/'symbols'/label)],name+'-symbolicate')
                toc=folder/'toc.xml';run(['xcrun','xctrace','export','--input',str(trace),'--toc','--output',str(toc)],name+'-toc')
                root=ET.parse(toc);target=root.find('.//target/process');assert target is not None and target.get('return-exit-status')=='0'
                pid=int(target.get('pid'));tables={e.get('schema') for e in root.findall('.//table')}
                required=['OSSignpostIntervals','time-profile'] if kind=='cpu' else ['OSSignpostIntervals','SwiftTaskStateTable','SwiftTasksInfoTable']
                assert set(required)<=tables
                for schema in required:
                    run(['xcrun','xctrace','export','--input',str(trace),'--xpath','/trace-toc/run[@number="1"]/data/table[@schema="'+schema+'"]','--output',str(folder/(schema+'.xml'))],name+'-'+schema)
                regions=intervals(folder/'OSSignpostIntervals.xml',pid)
                analysis=cpu(folder/'time-profile.xml',regions,pid) if kind=='cpu' else executors(folder/'SwiftTaskStateTable.xml',regions,pid)
                summary={'name':name,'capture':kind,'caller':caller,'phase':phase,'version':label,'position':pos+1,'PID':pid,'regions':regions,'analysis':analysis,'rawTraceSHA256':digest(archive),'loadAverageBefore':before,'loadAverageAfter':os.getloadavg(),'freeDiskBytesBefore':free}
                (folder/'analysis.json').write_text(json.dumps(summary,indent=2)+'\n');m['traces'].append(summary);save(m)
                shutil.rmtree(trace)

def summary(m):
    assert len(m['traces'])==32
    for p in m['phases'].values():
        labels=p['labels'];raw={r['name']:(cb.index_records(json.loads((OUT/r['result']).read_text())) if p['driver']=='common' else index_cpu(json.loads((OUT/r['result']).read_text()),p['driver'])) for r in p['runs']}
        indexed={}
        for name,rows in raw.items():
            if p['driver']=='common':indexed[name]=rows
            else:indexed[name]={(n,mode+'-'+c):{'name':n,'mode':mode+'-'+c,'medianNanoseconds':r[c+'MedianNanoseconds'],**{k:r[k] for k in ['outputBytes','fnv1aChecksum','samples','warmupSamples','repetitionsPerSample']}} for (n,mode),r in rows.items() for c in ['wall','cpu']}
        p['comparisons']=cb.comparisons(p['runs'],indexed,labels)
        p['reviewRequired']=[r['name']+'/'+r['mode'] for r in p['comparisons'] if r['requiresReview']]
        p['varianceReviewRequired']=[r['name']+'/'+r['mode'] for r in p['comparisons'] if r['varianceRequiresReview']]
        for row in p['comparisons']:
            key=row['name'],row['mode'];row['blockChangesPercent']=[]
            for block in range(1,4):
                values={l:[indexed[r['name']][key]['medianNanoseconds'] for r in p['runs'] if r['block']==block and r['version']==l] for l in labels}
                row['blockChangesPercent'].append((statistics.median(values[labels[1]])/statistics.median(values[labels[0]])-1)*100)
    m['status']='measured';(OUT/'date-trace-study.json').write_text(json.dumps(m,indent=2)+'\n')
    print(json.dumps({'status':'measured','traces':len(m['traces']),'phases':{k:{'median':len(v['reviewRequired']),'spread':len(v['varianceReviewRequired'])} for k,v in m['phases'].items()}}))

if __name__=='__main__':
    stage=sys.argv[1];m={'commands':cb.COMMANDS,'stages':{},'status':'in-progress'} if stage=='build' else load()
    m['stages'][stage]={'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        if stage=='build':build(m)
        elif stage=='measure':measure(m)
        elif stage in ['cpu','executor']:capture(m,stage)
        elif stage=='summary':summary(m)
        else:raise ValueError(stage)
    except BaseException as e:
        m['status']='failed';m['stages'][stage]['error']=repr(e);raise
    finally:
        m['stages'][stage]['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat();save(m)

    if stage=='summary':
        (OUT/'date-trace-study.json').write_text(json.dumps(m,indent=2)+'\n')
        assets={str(p.relative_to(OUT)):digest(p) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='SHA256SUMS'}
        (OUT/'SHA256SUMS').write_text(''.join(h+'  '+n+'\n' for n,h in assets.items()))
