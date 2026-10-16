#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Finite normalization/matching experiment; never merge diagnostic workflow."""
import datetime,hashlib,json,os,platform,shlex,shutil,statistics,subprocess,sys,tempfile
from pathlib import Path
import compare_benchmarks as cb
from optimization_index import index_public
MAIN='1c37b11f1487453772aaae9e6be0cfd75ab2af01'
CORE='6ea971af19d213c84e2f20701eb514262a0bd04e2fcf981286e7ec46abf8027a'
ROOT=cb.ROOT;OUT=cb.OUTPUT;ENV=cb.ENV;STATE=OUT/'optimization-state.json'
VARIANTS=['controlA','controlB','normalization','matching']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(m):STATE.write_text(json.dumps(m,indent=2)+'\n')
def run(command,name,**kwargs):
 print(name,flush=True);return cb.run(command,name,**kwargs)
def manifest(root):return [{'path':str(p.relative_to(root)),'sha256':sha(p)} for p in sorted((root/'Sources/Liquid').rglob('*.swift'))]
def setup(m):
 assert ENV.get('LIQUID_RUNNER_ENVIRONMENT')=='github-hosted'
 tools=ROOT/'Tools/OptimizationStudy'
 m.update({'workflowCommit':ENV['GITHUB_SHA'],'main':MAIN,'compiler':run(['xcrun','swift','--version'],'toolchain'),'platform':platform.platform(),'logicalCPUs':os.cpu_count(),'hardware':{k:run(['sysctl','-n',k],'host-'+k.replace('.','-')) for k in ['hw.model','hw.physicalcpu','hw.memsize','machdep.cpu.brand_string']},'sourceManifests':{},'librarySHA256':{},'binaries':{},'binaryIdentities':{},'phases':{},'toolSources':{str(p.relative_to(tools)):sha(p) for p in sorted(tools.rglob('*')) if p.is_file()}})
 shutil.copytree(tools,OUT/'frozen-tools');flags=[*shlex.split(ENV.get('LIQUID_SWIFTPM_FLAGS','')),'-Xswiftc','-g'];m['buildFlags']=flags
 run(['xcrun','swiftc','-swift-version','6','-parse-as-library',str(tools/'EquivalenceCheck.swift'),'-o',str(OUT/'EquivalenceCheck')],'equivalence-build')
 run([str(OUT/'EquivalenceCheck'),str(OUT/'equivalence.json')],'equivalence');equivalence=json.loads((OUT/'equivalence.json').read_text());assert equivalence=={'inputs':17844,'matchingChecks':463944,'normalizationFNV1a':'6c5d516fbf973470','patterns':26,'status':'passed'}
 temp=Path(tempfile.mkdtemp(prefix='liquid-optimization-',dir=ENV.get('RUNNER_TEMP')));m['scratch']=str(temp);assert shutil.disk_usage(temp).free>=7*1024**3
 harness=cb.git('show',cb.BASELINE+':'+cb.HARNESS);package=cb.git('show',cb.BASELINE+':Tools/Benchmarks/Package.swift');assert hashlib.sha256(harness).hexdigest()==cb.HARNESS_SHA256 and hashlib.sha256(package).hexdigest()==cb.MANIFEST_SHA256
 m['harnessSHA256']=cb.HARNESS_SHA256;m['manifestSHA256']=cb.MANIFEST_SHA256
 for label in VARIANTS:
  root=temp/label/'Swift-Liquid';root.mkdir(parents=True);cb.extract(MAIN,root);assert cb.library_hash(root)==CORE
  run([sys.executable,'-B',str(tools/'apply_candidate.py'),str(root),label],label+'-apply')
  m['sourceManifests'][label]=manifest(root);m['librarySHA256'][label]=cb.library_hash(root)
  (OUT/(label+'-RubyDateParser.swift')).write_bytes((root/'Sources/Liquid/Support/RubyDateParser.swift').read_bytes())
  if label in ['controlA','controlB']:assert m['librarySHA256'][label]==CORE
  if label!='controlB':
   for lane in ['native','reference']:
    args=[sys.executable,'-B','Scripts/ci.py','--lane',lane]
    if lane=='reference':args+=['--reference-path',ENV['LIQUID_REFERENCE_PATH']]
    try:run(args,label+'-'+lane,cwd=root)
    finally:
     if (root/'Artifacts'/lane).exists():shutil.copytree(root/'Artifacts'/lane,OUT/(label+'-'+lane))
    assert json.loads((OUT/(label+'-'+lane)/'receipt.json').read_text())['status']=='passed'
  (root/cb.HARNESS).write_bytes(harness);(root/'Tools/Benchmarks/Package.swift').write_bytes(package)
  public=root/'Tools/Optimization';(public/'Sources/OptimizationProbe').mkdir(parents=True);(public/'Sources/OptimizationProbe/main.swift').write_bytes((tools/'OptimizationProbe.swift').read_bytes());(public/'Package.swift').write_bytes(package.replace(b'LiquidBenchmarks',b'OptimizationProbe'))
  m['binaries'][label]={}
  for kind,pkg,product in [('common',root/'Tools/Benchmarks','LiquidBenchmarks'),('public',public,'OptimizationProbe')]:
   run(['xcrun','swift','build','-c','release','--package-path',str(pkg),*flags],label+'-'+kind+'-build');loc=run(['xcrun','swift','build','-c','release','--package-path',str(pkg),'--show-bin-path',*flags],label+'-'+kind+'-location').splitlines()[-1];binary=Path(loc)/product;m['binaries'][label][kind]=str(binary)
   dst=OUT/'binaries';dst.mkdir(exist_ok=True);shutil.copy2(binary,dst/(label+'-'+kind));m['binaryIdentities'][label+'/'+kind]={'sha256':sha(binary),'UUID':run(['xcrun','dwarfdump','--uuid',str(binary)],label+'-'+kind+'-uuid')}
  config=json.loads((tools/'workloads.json').read_text())
  for caller in ['actor','concurrent']:
   for order in ['forward','reverse']:
    name=label+'-validate-'+caller+'-'+order;dst=OUT/(name+'.json');run([m['binaries'][label]['public'],str(dst),caller,str(tools/'workloads.json'),order,'--validate-only'],name);index_public(json.loads(dst.read_text()),config,caller,order,True)
  save(m)
 for label in VARIANTS:
  assert [x for x in m['sourceManifests'][label] if x['path']!='Sources/Liquid/Support/RubyDateParser.swift']==[x for x in m['sourceManifests']['controlA'] if x['path']!='Sources/Liquid/Support/RubyDateParser.swift']
 m['allEightBuiltAndValidatedBeforeTiming']=True;save(m)
def index(data,driver,caller,order,config):
 return cb.index_records(data) if driver=='common' else index_public(data,config,caller,order)
def measure(m):
 assert m['allEightBuiltAndValidatedBeforeTiming'];config=json.loads((OUT/'frozen-tools/workloads.json').read_text())
 for block in range(1,4):
  comparisons=['normalization','matching','identical'];comparisons=comparisons[::-1] if block==2 else comparisons
  for comparison in comparisons:
   labels=['controlA','controlB' if comparison=='identical' else comparison]
   for driver,caller in [('common','ordinary')]+[('public',c) for c in (['concurrent','actor'] if block==2 else ['actor','concurrent'])]:
    key=comparison+'-'+driver+'-'+caller;p=m['phases'].setdefault(key,{'driver':driver,'caller':caller,'labels':labels,'runs':[]})
    for pos,label in enumerate([labels[0],labels[1],labels[1],labels[0]],1):
     order=('forward' if (pos%2==1)==(block!=2) else 'reverse') if driver=='public' else 'original';name=f'{key}-{block}-{pos}-{label}';dst=OUT/(name+'.json');args=[m['binaries'][label][driver],str(dst)]
     if driver=='public':args += [caller,str(ROOT/'Tools/OptimizationStudy/workloads.json'),order]
     load=os.getloadavg();run(args,name);index(json.loads(dst.read_text()),driver,caller,order,config);p['runs'].append({'name':name,'version':label,'block':block,'position':pos,'recordOrder':order,'result':dst.name,'loadAverageBefore':load,'loadAverageAfter':os.getloadavg()});save(m)
def summarize(m):
 config=json.loads((OUT/'frozen-tools/workloads.json').read_text());total=0
 for p in m['phases'].values():
  assert len(p['runs'])==12;records={r['name']:index(json.loads((OUT/r['result']).read_text()),p['driver'],p['caller'],r['recordOrder'],config) for r in p['runs']};p['comparisons']=cb.comparisons(p['runs'],records,p['labels']);total+=len(p['comparisons']);p['reviewRequired']=[r['name']+'/'+r['mode'] for r in p['comparisons'] if r['requiresReview']];p['varianceReviewRequired']=[r['name']+'/'+r['mode'] for r in p['comparisons'] if r['varianceRequiresReview']]
  for row in p['comparisons']:
   row['blockChangesPercent']=[];key=row['name'],row['mode']
   for block in range(1,4):
    values={l:[records[r['name']][key]['medianNanoseconds'] for r in p['runs'] if r['block']==block and r['version']==l] for l in p['labels']};row['blockChangesPercent'].append((statistics.median(values[p['labels'][1]])/statistics.median(values[p['labels'][0]])-1)*100)
 assert len(m['phases'])==9 and sum(len(p['runs']) for p in m['phases'].values())==108 and total==222
 m['status']='measured';save(m);print(json.dumps({'runs':108,'comparisons':222,'flags':{k:[len(p['reviewRequired']),len(p['varianceReviewRequired'])] for k,p in m['phases'].items()}}))
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
  (OUT/'optimization-study.json').write_text(json.dumps(m,indent=2)+'\n');files={str(p.relative_to(OUT)):sha(p) for p in sorted(OUT.rglob('*')) if p.is_file() and p.name!='SHA256SUMS'};(OUT/'SHA256SUMS').write_text(''.join(h+'  '+p+'\n' for p,h in files.items()))
