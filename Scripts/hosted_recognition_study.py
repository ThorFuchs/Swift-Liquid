#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Frozen controlled date component study; diagnostic branch only."""
import datetime,hashlib,json,os,platform,shlex,shutil,statistics,subprocess,sys,tempfile
from pathlib import Path
import compare_benchmarks as cb
from date_trace_benchmark_index import index_cpu
from recognition_benchmark_index import index_components
BASE='9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e'
MAIN='1ae8df16c6cc02caba75f83d6a46ea52f74a7d56'
CORE='6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a'
ROOT=cb.ROOT;OUT=cb.OUTPUT;ENV=cb.ENV;STATE=OUT/'recognition-study-state.json';CONFIG=None
VERSIONS={'v130':BASE,'mainA':MAIN,'mainB':MAIN}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(m):STATE.write_text(json.dumps(m,indent=2)+'\n')
def run(command,name,**kwargs):
 print(name,flush=True);return cb.run(command,name,**kwargs)
def source_manifest(root):return [{'path':str(p.relative_to(root)),'sha256':sha(p)} for p in sorted((root/'Sources/Liquid').rglob('*.swift'))]
def setup(m):
 assert ENV.get('LIQUID_RUNNER_ENVIRONMENT')=='github-hosted'
 m.update({'workflowCommit':ENV['GITHUB_SHA'],'versions':VERSIONS,'compiler':run(['xcrun','swift','--version'],'toolchain'),'platform':platform.platform(),'logicalCPUs':os.cpu_count(),'hardware':{k:run(['sysctl','-n',k],'host-'+k.replace('.','-')) for k in ['hw.model','hw.physicalcpu','hw.memsize','machdep.cpu.brand_string']},'binaries':{},'sourceManifests':{},'librarySHA256':{},'augmentedManifests':{},'augmentedLibrarySHA256':{},'binaryIdentities':{},'phases':{}})
 temp=Path(tempfile.mkdtemp(prefix='liquid-recognition-',dir=ENV.get('RUNNER_TEMP')));m['scratch']=str(temp);assert shutil.disk_usage(temp).free>=6*1024**3
 harness=cb.git('show',BASE+':'+cb.HARNESS);manifest=cb.git('show',BASE+':Tools/Benchmarks/Package.swift');assert hashlib.sha256(harness).hexdigest()==cb.HARNESS_SHA256 and hashlib.sha256(manifest).hexdigest()==cb.MANIFEST_SHA256
 m['harnessSHA256']=cb.HARNESS_SHA256;m['manifestSHA256']=cb.MANIFEST_SHA256;tools=ROOT/'Tools/DateRecognitionStudy'
 source={k:(tools/v).read_bytes() for k,v in [('bridge','LibraryBridge.swift'),('component','RecognitionProbe.swift'),('public','DateCPUProbe.swift'),('inputs','inputs.json')]};m['inputAndProbeSHA256']={k:hashlib.sha256(v).hexdigest() for k,v in source.items()}
 assert m['inputAndProbeSHA256']['public']=='cf311a2d8fc33a5d7f78f5bc52797aaff58c71e4d409b7022c3b5ac90ba002a9'
 for k,v in source.items():(OUT/(k+'-source')).write_bytes(v)
 config=json.loads(source['inputs']);flags=[*shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS','')),'-Xswiftc','-g'];m['buildFlags']=flags
 for label,commit in VERSIONS.items():
  original=temp/label/'original/Swift-Liquid';original.mkdir(parents=True);cb.extract(commit,original);m['sourceManifests'][label]=source_manifest(original);m['librarySHA256'][label]=cb.library_hash(original)
  if label.startswith('main'):assert m['librarySHA256'][label]==CORE
  if label=='mainA':
   try:run([sys.executable,'-B','Scripts/ci.py','--lane','development'],'original-main-development',cwd=original)
   finally:
    if (original/'Artifacts/development').exists():shutil.copytree(original/'Artifacts/development',OUT/'original-main-development')
   assert json.loads((OUT/'original-main-development/receipt.json').read_text())['status']=='passed'
  (original/cb.HARNESS).write_bytes(harness);(original/'Tools/Benchmarks/Package.swift').write_bytes(manifest)
  public=original/'Tools/DateCPUStudy';(public/'Sources/LiquidDateCPUProbe').mkdir(parents=True);(public/'Sources/LiquidDateCPUProbe/main.swift').write_bytes(source['public']);(public/'Package.swift').write_bytes(manifest.replace(b'LiquidBenchmarks',b'LiquidDateCPUProbe'))
  augmented=temp/label/'augmented/Swift-Liquid';augmented.mkdir(parents=True);cb.extract(commit,augmented);(augmented/'Sources/Liquid/DateCostBridge.swift').write_bytes(source['bridge']);m['augmentedManifests'][label]=source_manifest(augmented);m['augmentedLibrarySHA256'][label]=cb.library_hash(augmented)
  assert [x for x in m['augmentedManifests'][label] if x['path']!='Sources/Liquid/DateCostBridge.swift']==m['sourceManifests'][label]
  if label=='mainA':
   try:run([sys.executable,'-B','Scripts/ci.py','--lane','development'],'augmented-main-development',cwd=augmented)
   finally:
    if (augmented/'Artifacts/development').exists():shutil.copytree(augmented/'Artifacts/development',OUT/'augmented-main-development')
   assert json.loads((OUT/'augmented-main-development/receipt.json').read_text())['status']=='passed'
  component=augmented/'Tools/Recognition';(component/'Sources/LiquidDateRecognitionProbe').mkdir(parents=True);(component/'Sources/LiquidDateRecognitionProbe/main.swift').write_bytes(source['component']);(component/'Package.swift').write_bytes(manifest.replace(b'LiquidBenchmarks',b'LiquidDateRecognitionProbe'))
  m['binaries'][label]={}
  for kind,pkg,product in [('common',original/'Tools/Benchmarks','LiquidBenchmarks'),('public',public,'LiquidDateCPUProbe'),('component',component,'LiquidDateRecognitionProbe')]:
   run(['xcrun','swift','build','-c','release','--package-path',str(pkg),*flags],label+'-'+kind+'-build');loc=run(['xcrun','swift','build','-c','release','--package-path',str(pkg),'--show-bin-path',*flags],label+'-'+kind+'-location').splitlines()[-1];binary=Path(loc)/product;m['binaries'][label][kind]=str(binary)
   dst=OUT/'binaries';dst.mkdir(exist_ok=True);shutil.copy2(binary,dst/(label+'-'+kind));m['binaryIdentities'][label+'/'+kind]={'sha256':sha(binary),'UUID':run(['xcrun','dwarfdump','--uuid',str(binary)],label+'-'+kind+'-uuid')}
   if kind=='component':
    symbols=OUT/'symbols'/label;symbols.mkdir(parents=True);run(['xcrun','dsymutil',str(binary),'-o',str(symbols/(product+'.dSYM'))],label+'-component-dsym');nm=run(['xcrun','nm','-nm',str(binary)],label+'-component-symbols');assert 'LiquidDateCostProbe' in nm
  for caller in ['actor','concurrent']:
   for order in ['forward','reverse']:
    name=label+'-validate-'+caller+'-'+order;dst=OUT/(name+'.json');run([m['binaries'][label]['component'],str(dst),caller,str(tools/'inputs.json'),order,'--validate-only'],name);index_components(json.loads(dst.read_text()),config,caller,order,validation=True)
  save(m)
 assert m['librarySHA256']['mainA']==m['librarySHA256']['mainB'] and m['augmentedLibrarySHA256']['mainA']==m['augmentedLibrarySHA256']['mainB']
 m['allNineBuiltAndValidatedBeforeTiming']=True;save(m)
def index(data,driver,caller,order,config):
 if driver=='common':return cb.index_records(data)
 rows=index_cpu(data,caller) if driver=='public' else index_components(data,config,caller,order)
 return {(name,mode+'-'+clock):{'name':name,'mode':mode+'-'+clock,'medianNanoseconds':r[clock+'MedianNanoseconds'],**{k:r[k] for k in ['outputBytes','fnv1aChecksum','samples','warmupSamples','repetitionsPerSample']}} for (name,mode),r in rows.items() for clock in ['wall','cpu']}
def measure(m):
 assert m['allNineBuiltAndValidatedBeforeTiming'];config=json.loads((OUT/'inputs-source').read_text())
 for block in range(1,4):
  phases=[('common','ordinary'),('public','actor'),('public','concurrent')]+[('component',c) for c in (['concurrent','actor'] if block==2 else ['actor','concurrent'])]
  for driver,caller in phases:
   for kind,labels in [('release',['v130','mainA']),('identical',['mainA','mainB'])]:
    key=kind+'-'+driver+'-'+caller;p=m['phases'].setdefault(key,{'driver':driver,'caller':caller,'labels':labels,'runs':[]})
    for pos,label in enumerate([labels[0],labels[1],labels[1],labels[0]],1):
     order=('forward' if (pos%2==1)==(block!=2) else 'reverse') if driver=='component' else 'original';name=f'{key}-{block}-{pos}-{label}';dst=OUT/(name+'.json');cmd=[m['binaries'][label][driver],str(dst)]
     if driver=='public':cmd.append(caller)
     if driver=='component':cmd += [caller,str(ROOT/'Tools/DateRecognitionStudy/inputs.json'),order]
     load=os.getloadavg();run(cmd,name);index(json.loads(dst.read_text()),driver,caller,order,config);p['runs'].append({'name':name,'version':label,'block':block,'position':pos,'recordOrder':order,'result':dst.name,'loadAverageBefore':load,'loadAverageAfter':os.getloadavg()});save(m)
def summarize(m):
 config=json.loads((OUT/'inputs-source').read_text());total=0
 for p in m['phases'].values():
  assert len(p['runs'])==12;records={r['name']:index(json.loads((OUT/r['result']).read_text()),p['driver'],p['caller'],r['recordOrder'],config) for r in p['runs']};p['comparisons']=cb.comparisons(p['runs'],records,p['labels']);total+=len(p['comparisons']);p['reviewRequired']=[r['name']+'/'+r['mode'] for r in p['comparisons'] if r['requiresReview']];p['varianceReviewRequired']=[r['name']+'/'+r['mode'] for r in p['comparisons'] if r['varianceRequiresReview']]
  for row in p['comparisons']:
   row['blockChangesPercent']=[];key=row['name'],row['mode']
   for block in range(1,4):
    values={l:[records[r['name']][key]['medianNanoseconds'] for r in p['runs'] if r['block']==block and r['version']==l] for l in p['labels']};row['blockChangesPercent'].append((statistics.median(values[p['labels'][1]])/statistics.median(values[p['labels'][0]])-1)*100)
 assert sum(len(p['runs']) for p in m['phases'].values())==120 and total==404
 m['status']='measured';save(m);(OUT/'recognition-study.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps({'runs':120,'comparisons':404,'flags':{k:[len(p['reviewRequired']),len(p['varianceReviewRequired'])] for k,p in m['phases'].items()}}))
if __name__=='__main__':
 stage=sys.argv[1];m={'status':'in-progress','commands':cb.COMMANDS,'stages':{}} if stage=='setup' else json.loads(STATE.read_text());cb.COMMANDS[:]=m['commands'];m['commands']=cb.COMMANDS;m['stages'][stage]={'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat()}
 try:
  if stage=='setup':setup(m)
  elif stage=='measure':measure(m)
  elif stage=='summary':summarize(m)
  else:raise ValueError(stage)
 except BaseException as error:m['status']='failed';m['stages'][stage]['error']=repr(error);raise
 finally:m['stages'][stage]['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat();save(m)
 if stage=='summary':
  (OUT/'recognition-study.json').write_text(json.dumps(m,indent=2)+'\n');files={str(p.relative_to(OUT)):sha(p) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='SHA256SUMS'};(OUT/'SHA256SUMS').write_text(''.join(h+'  '+p+'\n' for p,h in files.items()))
