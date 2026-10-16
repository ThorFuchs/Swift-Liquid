# SPDX-License-Identifier: Apache-2.0
"""Coordinated attachment; benchmark observations are never repeated."""
import hashlib,json,os,platform,shlex,shutil,signal,subprocess,sys,tarfile,tempfile,time,traceback,uuid
from pathlib import Path
from xml.etree import ElementTree as ET
import compare_benchmarks as cb
import hosted_date_trace_study as original
from date_trace_benchmark_index import SOURCES
from trace_analysis import Table,intervals,cpu,executors
OUT=cb.OUTPUT;ROOT=cb.ROOT;ENV=cb.ENV;CURRENT=None

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(m):(OUT/'attached-state.json').write_text(json.dumps(m,indent=2)+'\n')
def stop(process):
 for sig,seconds in [(signal.SIGINT,5),(signal.SIGTERM,5),(signal.SIGKILL,5)]:
  if process.poll() is not None:return
  try:os.killpg(process.pid,sig)
  except ProcessLookupError:return
  try:process.wait(timeout=seconds)
  except subprocess.TimeoutExpired:pass

def run(cmd,name,cwd=ROOT,limit=180):
 print(name,flush=True);start=time.monotonic()
 with (OUT/(name+'.log')).open('w') as stream:
  process=subprocess.Popen(cmd,cwd=cwd,env=ENV,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
  try:code=process.wait(timeout=limit)
  except subprocess.TimeoutExpired:stop(process);code=124
 cb.COMMANDS.append({'name':name,'command':cmd,'exitCode':code,'wallSeconds':time.monotonic()-start,'timeoutSeconds':limit})
 if CURRENT is not None:save(CURRENT)
 if code:raise RuntimeError(name+' exit '+str(code))
 return (OUT/(name+'.log')).read_text(errors='replace').strip()

def attached(binary,args,folder,name,kind):
 folder.mkdir(exist_ok=True);coord=folder/'coordination';coord.mkdir();children=[];key='org.swift-liquid.capture.'+uuid.uuid4().hex;pid=None;code=124;start=time.monotonic()
 duration='20s' if kind=='cpu' else '5s';template='Time Profiler' if kind=='cpu' else 'Swift Concurrency'
 command=None
 try:
  with (folder/'target-stdout.log').open('w') as targetlog,(folder/'notification.log').open('w') as notification,(OUT/(name+'-record.log')).open('w') as recordlog:
   target=subprocess.Popen([str(binary),*args,str(coord)],stdout=targetlog,stderr=subprocess.STDOUT,env=ENV,start_new_session=True);children.append(target);pid=target.pid;deadline=time.monotonic()+30
   while not (coord/'ready').exists():
    assert target.poll() is None and time.monotonic()<deadline;time.sleep(.02)
   listener=subprocess.Popen(['/usr/bin/notifyutil','-1',key],stdout=notification,stderr=subprocess.STDOUT,start_new_session=True);children.append(listener)
   command=['xcrun','xctrace','record','--template',template,'--output',str(folder/'capture.trace'),'--no-prompt','--time-limit',duration,'--notify-tracing-started',key,'--attach',str(pid)]
   print(name+'-record',flush=True);recorder=subprocess.Popen(command,stdout=recordlog,stderr=subprocess.STDOUT,env=ENV,start_new_session=True);children.append(recorder)
   listener.wait(timeout=30);assert listener.returncode==0;(coord/'start').write_text('start')
   try:code=recorder.wait(timeout=180)
   except subprocess.TimeoutExpired:stop(recorder);code=124
   assert code==0 and (coord/'done').exists(),(name,code,'missing completed work')
   (coord/'release').write_text('release');target.wait(timeout=30);assert target.returncode==0
  logs=(OUT/(name+'-record.log')).read_text()+(folder/'target-stdout.log').read_text()
  assert 'Reached specified time limit' in logs and 'Output file saved' in logs
  assert not any(x in logs.lower() for x in ['quarantined','events were dropped','data was lost','buffer overflow'])
  return {'PID':pid,'targetExitCode':target.returncode,'recordExitCode':code,'recordingLimit':duration,'coordination':'Darwin tracing-start notification, target holds until recorder stops'}
 finally:
  for child in reversed(children):stop(child)
  cb.COMMANDS.append({'name':name+'-record','command':command,'exitCode':code,'wallSeconds':time.monotonic()-start,'timeoutSeconds':180})
  if CURRENT is not None:save(CURRENT)

def setup():
 global CURRENT
 initial=json.loads((OUT/'trace-study-state.json').read_text());assert initial['workflowCommit']=='5da238f5a8228fc2dba263c5f8b03a33820f5aba' and initial['versions']==original.VERSIONS
 assert sum(len(p['runs']) for p in initial['phases'].values())==72 and len(initial['traces'])==6
 m=dict(initial);m['initialTraceCohort']=m.pop('traces');m['initialDebugArtifacts']=m.pop('debugArtifacts');m['debugArtifacts']={};m['traces']=[];m['captureFailures']=[];m['commands']=cb.COMMANDS;m['status']='attached-captures-in-progress';m['attachedWorkflowCommit']=ENV['GITHUB_SHA'];CURRENT=m
 m['attachedHost']={'compiler':run(['xcrun','swift','--version'],'attached-toolchain'),'platform':platform.platform(),'logicalCPUs':os.cpu_count(),'hardware':{k:run(['sysctl','-n',k],'attached-'+k.replace('.','-')) for k in ['hw.model','hw.physicalcpu','hw.memsize','machdep.cpu.brand_string']}}
 m['initialStateSHA256']=sha(OUT/'trace-study-state.json');(OUT/'initial-capture-cohort').mkdir()
 for p in list(OUT.glob('trace-*')):
  if p.is_dir():p.rename(OUT/'initial-capture-cohort'/p.name)
 (OUT/'symbols').rename(OUT/'initial-symbols');assert ENV['LIQUID_RUNNER_ENVIRONMENT']=='github-hosted' and shutil.disk_usage(OUT).free>=6*1024**3
 temp=Path(tempfile.mkdtemp(prefix='liquid-attached-',dir=ENV.get('RUNNER_TEMP')));m['attachedScratch']=str(temp)
 cap=temp/'AttachedCapability';run(['xcrun','swiftc','-swift-version','6','-parse-as-library','-O','-g',str(ROOT/'Tools/DateTraceStudy/AttachedCapability.swift'),'-o',str(cap)],'attached-capability-build')
 info=attached(cap,[],OUT/'attached-capability','attached-capability','executor')
 for schema in ['OSSignpostIntervals','SwiftTaskStateTable']:
  run(['xcrun','xctrace','export','--input',str(OUT/'attached-capability/capture.trace'),'--xpath','/trace-toc/run[@number="1"]/data/table[@schema="'+schema+'"]','--output',str(OUT/'attached-capability'/(schema+'.xml'))],'attached-capability-'+schema)
 sp=Table(OUT/'attached-capability/OSSignpostIntervals.xml');r=next(r for r in sp.rows if sp.text(r['name'])=='CapabilityBatch');begin=sp.number(r['start']);scope={'capability':{'start':begin,'end':begin+sp.number(r['duration'])}}
 result=executors(OUT/'attached-capability/SwiftTaskStateTable.xml',scope,info['PID'])
 assert result['capability']['observedRunningSegmentTransitions']['Main Actor -> Global Concurrent Executor']==100 and result['capability']['observedRunningSegmentTransitions']['Global Concurrent Executor -> Main Actor']==100
 m['attachedCapability']={'process':info,'analysis':result}
 with tarfile.open(OUT/'attached-capability/original.trace.tar.gz','w:gz') as archive:archive.add(OUT/'attached-capability/capture.trace',arcname='capture.trace')
 shutil.rmtree(OUT/'attached-capability/capture.trace')
 probe=(ROOT/'Tools/DateTraceStudy/AttachedDateTraceProbe.swift').read_bytes();m['attachedProbeSHA256']=hashlib.sha256(probe).hexdigest();(OUT/'attached-probe-source.swift').write_bytes(probe)
 manifest=cb.git('show',original.BASE+':Tools/Benchmarks/Package.swift');flags=[*shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS','')),'-Xswiftc','-g'];m['attachedBuildFlags']=flags
 for label,commit in original.VERSIONS.items():
  root=temp/label/'Swift-Liquid';root.mkdir(parents=True);cb.extract(commit,root);assert cb.library_hash(root)==initial['librarySHA256'][label]
  product='LiquidAttachedDateTraceProbe';pkg=root/'Tools/AttachedTrace';(pkg/('Sources/'+product)).mkdir(parents=True);(pkg/'Package.swift').write_bytes(manifest.replace(b'"LiquidBenchmarks"',('"'+product+'"').encode()));(pkg/('Sources/'+product+'/main.swift')).write_bytes(probe)
  run(['xcrun','swift','build','-c','release','--package-path',str(pkg),*flags],label+'-attached-build');loc=run(['xcrun','swift','build','-c','release','--package-path',str(pkg),'--show-bin-path',*flags],label+'-attached-binary').splitlines()[-1];binary=Path(loc)/product;m['binaries'][label]['trace']=str(binary)
  symbols=OUT/'symbols'/label;symbols.mkdir(parents=True);run(['xcrun','dsymutil',str(binary),'-o',str(symbols/(product+'.dSYM'))],label+'-attached-dsym');shutil.copy2(binary,symbols/product)
  m['debugArtifacts'][label+'/'+product]={'sha256':sha(binary),'UUID':run(['xcrun','dwarfdump','--uuid',str(binary)],label+'-attached-uuid')};save(m)
 m['allAttachedBinariesBuiltBeforeCaptures']=True;save(m)

def one(m,kind,caller,phase,pos,label):
 name=f'trace-{kind}-{caller}-{phase}-{pos+1}-{label}';folder=OUT/name;folder.mkdir();free=shutil.disk_usage(folder).free;assert free>=2*1024**3
 before=os.getloadavg();info=attached(m['binaries'][label]['trace'],[caller,kind,str(folder/'outputs.json')],folder,name,kind)
 outputs=json.loads((folder/'outputs.json').read_text());assert outputs['configuration']=='release' and outputs['caller']==caller and outputs['capture']==kind and len(outputs['records'])==6
 assert {r['name'] for r in outputs['records']}=={n+'-'+v for n in ['iso','epoch','filter'] for v in ['source','reused']}
 assert 'Trace probe complete: '+caller+' '+kind in (folder/'target-stdout.log').read_text()
 count,warmups=(20000,100) if kind=='cpu' else (100,10)
 for r in outputs['records']:
  payload=SOURCES[r['name'].split('-')[0]][1].encode();h=14695981039346656037
  for _ in range(count+warmups):
   for b in payload:h=((h^b)*1099511628211)&((1<<64)-1)
  assert (r['iterations'],r['warmupIterations'],r['outputBytes'],r['fnv1aChecksum'])==(count,warmups,len(payload),format(h,'x'))
 raw=folder/'original.trace.tar.gz'
 with tarfile.open(raw,'w:gz') as archive:archive.add(folder/'capture.trace',arcname='capture.trace')
 run(['xcrun','xctrace','symbolicate','--input',str(folder/'capture.trace'),'--dsym',str(OUT/'symbols'/label)],name+'-symbolicate')
 run(['xcrun','xctrace','export','--input',str(folder/'capture.trace'),'--toc','--output',str(folder/'toc.xml')],name+'-toc');toc=ET.parse(folder/'toc.xml');target=toc.find('.//target/process');assert int(target.get('pid'))==info['PID']
 for schema in (['OSSignpostIntervals','time-profile'] if kind=='cpu' else ['OSSignpostIntervals','SwiftTaskStateTable','SwiftTasksInfoTable']):
  run(['xcrun','xctrace','export','--input',str(folder/'capture.trace'),'--xpath','/trace-toc/run[@number="1"]/data/table[@schema="'+schema+'"]','--output',str(folder/(schema+'.xml'))],name+'-'+schema)
 regions=intervals(folder/'OSSignpostIntervals.xml',info['PID']);analysis=cpu(folder/'time-profile.xml',regions,info['PID']) if kind=='cpu' else executors(folder/'SwiftTaskStateTable.xml',regions,info['PID'])
 result={'name':name,'capture':kind,'caller':caller,'phase':phase,'version':label,'position':pos+1,'PID':info['PID'],'process':info,'regions':regions,'analysis':analysis,'rawTraceSHA256':sha(raw),'loadAverageBefore':before,'loadAverageAfter':os.getloadavg(),'freeDiskBytesBefore':free}
 (folder/'analysis.json').write_text(json.dumps(result,indent=2)+'\n');m['traces'].append(result);save(m);shutil.rmtree(folder/'capture.trace')

def captures(kind):
 global CURRENT
 m=json.loads((OUT/'attached-state.json').read_text());cb.COMMANDS[:]=m['commands'];m['commands']=cb.COMMANDS;CURRENT=m;consecutive=0
 for caller in ['actor','concurrent']:
  for phase,labels in [('release',['v130','mainA']),('identical',['mainA','mainB'])]:
   for pos,label in enumerate([labels[0],labels[1],labels[1],labels[0]]):
    name=f'trace-{kind}-{caller}-{phase}-{pos+1}-{label}'
    try:one(m,kind,caller,phase,pos,label);consecutive=0
    except Exception as error:
     consecutive+=1;m['captureFailures'].append({'name':name,'error':repr(error),'traceback':traceback.format_exc()});save(m);print('INVALID CAPTURE: '+name+' '+repr(error),flush=True)
     if consecutive>=3:raise RuntimeError('Three consecutive invalid captures; retain partial data')
 save(m)

def finish():
 m=json.loads((OUT/'attached-state.json').read_text());assert len(m['traces'])+len(m['captureFailures'])==32
 if m['captureFailures']:m['status']='incomplete-attached-cohort';save(m);raise RuntimeError('Incomplete captures are not qualification successes')
 original.summary(m);m['status']='measured';save(m);(OUT/'attached-date-trace-study.json').write_text(json.dumps(m,indent=2)+'\n')
 files={str(p.relative_to(OUT)):sha(p) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='SHA256SUMS'};(OUT/'SHA256SUMS').write_text(''.join(h+'  '+n+'\n' for n,h in files.items()))
if __name__=='__main__':
 stage=sys.argv[1]
 if stage=='setup':setup()
 elif stage in ['cpu','executor']:captures(stage)
 elif stage=='finish':finish()
 else:raise ValueError(stage)
