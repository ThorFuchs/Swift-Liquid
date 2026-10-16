# SPDX-License-Identifier: Apache-2.0
"""Capture recovery only; never repeats the retained untraced cohort."""
import datetime,hashlib,json,os,platform,shutil,signal,subprocess,sys,tarfile,time,traceback
from pathlib import Path
from xml.etree import ElementTree as ET
import compare_benchmarks as cb
import hosted_date_trace_study as original
from date_trace_benchmark_index import SOURCES
from trace_analysis import Table,intervals,cpu,executors
OUT=cb.OUTPUT;ENV=cb.ENV;ROOT=cb.ROOT
class CaptureCommandFailure(RuntimeError):pass
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(m):(OUT/'recovery-state.json').write_text(json.dumps(m,indent=2)+'\n')
CURRENT=None
def run(cmd,name,cwd=ROOT,required=True):
    print(name,flush=True);started=time.monotonic();log=OUT/(name+'.log')
    with log.open('w') as stream:
        process=subprocess.Popen(cmd,cwd=cwd,env=ENV,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        try:code=process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            for sig,seconds in [(signal.SIGINT,10),(signal.SIGTERM,5),(signal.SIGKILL,5)]:
                if process.poll() is not None:break
                try:os.killpg(process.pid,sig)
                except ProcessLookupError:break
                try:process.wait(timeout=seconds)
                except subprocess.TimeoutExpired:pass
            code=124
    cb.COMMANDS.append({'name':name,'command':cmd,'exitCode':code,'wallSeconds':time.monotonic()-started,'timeoutSeconds':180})
    if CURRENT is not None:save(CURRENT)
    if code and required:raise CaptureCommandFailure(name+' exit '+str(code))
    return log.read_text(errors='replace').strip()

def record_one(m,kind,caller,phase,pos,label):
    binaries=m['binaries']
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

def setup():
    global CURRENT
    initial=json.loads((OUT/'trace-study-state.json').read_text());assert initial['workflowCommit']=='5da238f5a8228fc2dba263c5f8b03a33820f5aba'
    assert sum(len(p['runs']) for p in initial['phases'].values())==72 and len(initial['traces'])==6
    assert initial['versions']==original.VERSIONS
    m=dict(initial);m['initialTraceCohort']=m.pop('traces');m['traces']=[];m['captureFailures']=[];m['commands']=cb.COMMANDS;m['recoveryWorkflowCommit']=ENV['GITHUB_SHA'];m['status']='recovery-in-progress'
    m['recoveryHost']={'toolchain':run(['xcrun','swift','--version'],'recovery-toolchain'),'platform':platform.platform(),'logicalCPUs':os.cpu_count(),'hardware':{k:run(['sysctl','-n',k],'recovery-'+k.replace('.','-')) for k in ['hw.model','hw.physicalcpu','hw.memsize','machdep.cpu.brand_string']}}
    m['initialStateSHA256']=digest(OUT/'trace-study-state.json');CURRENT=m
    archive=OUT/'initial-capture-cohort';archive.mkdir()
    for p in list(OUT.glob('trace-*')):
        if p.is_dir():p.rename(archive/p.name)
    for label in ['v130','mainA','mainB']:
        binary=OUT/'symbols'/label/'LiquidDateTraceProbe';assert digest(binary)==initial['debugArtifacts'][label+'/LiquidDateTraceProbe']['sha256'];binary.chmod(0o755);m['binaries'][label]['trace']=str(binary)
    assert ENV.get('LIQUID_RUNNER_ENVIRONMENT')=='github-hosted' and __import__('shutil').disk_usage(OUT).free>=6*1024**3
    source=ROOT/'Tools/DateTraceStudy/HostedTraceCapability.swift';binary=OUT/'RecoveryCapability'
    run(['xcrun','swiftc','-swift-version','6','-parse-as-library','-O','-g',str(source),'-o',str(binary)],'recovery-capability-build')
    trace=OUT/'recovery-capability.trace';stdout=OUT/'recovery-capability-output.log'
    run(['xcrun','xctrace','record','--template','Swift Concurrency','--output',str(trace),'--no-prompt','--time-limit','30s','--target-stdout',str(stdout),'--launch','--',str(binary)],'recovery-capability-record')
    text=(OUT/'recovery-capability-record.log').read_text()+stdout.read_text();assert 'Target app exited' in text and 'Capability result verified: 100' in text and 'Reached specified time limit' not in text and 'quarantined' not in text.lower()
    for schema in ['SwiftTaskStateTable','OSSignpostIntervals']:
        run(['xcrun','xctrace','export','--input',str(trace),'--xpath','/trace-toc/run[@number="1"]/data/table[@schema="'+schema+'"]','--output',str(OUT/('recovery-capability-'+schema+'.xml'))],'recovery-capability-'+schema)
    sp=Table(OUT/'recovery-capability-OSSignpostIntervals.xml');r=next(r for r in sp.rows if sp.text(r['name'])=='CapabilityBatch');begin=sp.number(r['start']);region={'capability':{'start':begin,'end':begin+sp.number(r['duration'])}};pid=sp.pid(r['process'])
    result=executors(OUT/'recovery-capability-SwiftTaskStateTable.xml',region,pid)
    assert result['capability']['observedRunningSegmentTransitions']['Main Actor -> Global Concurrent Executor']==100
    assert result['capability']['observedRunningSegmentTransitions']['Global Concurrent Executor -> Main Actor']==100
    m['recoveryCapability']=result
    with tarfile.open(OUT/'recovery-capability.trace.tar.gz','w:gz') as t:t.add(trace,arcname='recovery-capability.trace')
    __import__('shutil').rmtree(trace);save(m)

def captures(kind):
    global CURRENT
    m=json.loads((OUT/'recovery-state.json').read_text());cb.COMMANDS[:]=m['commands'];m['commands']=cb.COMMANDS;CURRENT=m;consecutive=0
    for caller in ['actor','concurrent']:
        for phase,labels in [('release',['v130','mainA']),('identical',['mainA','mainB'])]:
            for pos,label in enumerate([labels[0],labels[1],labels[1],labels[0]]):
                name=f'trace-{kind}-{caller}-{phase}-{pos+1}-{label}'
                try:record_one(m,kind,caller,phase,pos,label);consecutive=0
                except Exception as error:
                    consecutive+=1;m['captureFailures'].append({'name':name,'error':repr(error),'traceback':traceback.format_exc()});save(m);print('CAPTURE INVALID: '+name+' '+repr(error),flush=True)
                    if consecutive>=3:raise RuntimeError('Three consecutive invalid captures; retain partial cohort')
    save(m)

def finish():
    m=json.loads((OUT/'recovery-state.json').read_text());cb.COMMANDS[:]=m['commands'];m['commands']=cb.COMMANDS
    assert len(m['traces'])+len(m['captureFailures'])==32
    if m['captureFailures']:
        m['status']='incomplete-capture-cohort';save(m);raise RuntimeError('Missing captures remain explicit; not qualified')
    original.summary(m);m['status']='measured';save(m);(OUT/'date-trace-recovery.json').write_text(json.dumps(m,indent=2)+'\n')
    files={str(p.relative_to(OUT)):digest(p) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='SHA256SUMS'}
    (OUT/'SHA256SUMS').write_text(''.join(h+'  '+n+'\n' for n,h in files.items()))
if __name__=='__main__':
    stage=sys.argv[1]
    if stage=='setup':setup()
    elif stage in ['cpu','executor']:captures(stage)
    elif stage=='finish':finish()
    else:raise ValueError(stage)
