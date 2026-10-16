# SPDX-License-Identifier: Apache-2.0
from functools import lru_cache
@lru_cache(None)
def checksum(payload,count):
 h=14695981039346656037
 for _ in range(count):
  for b in payload:h=((h^b)*1099511628211)&((1<<64)-1)
 return format(h,'x')
def index_public(data,config,caller,order,validation=False):
 assert data['configuration']=='release' and data['caller']==caller and data['recordOrder']==order and data['kind']==('validation' if validation else 'measurement')
 expected={(w['name'],m):w['expected'].encode() for w in config['workloads'] for m in ['source','reused']}
 keys=list(expected);keys=keys if order=='forward' else keys[::-1]
 assert [(r['name'],r['mode']) for r in data['records']]==keys
 rows={}
 for r in data['records']:
  payload=expected[r['name'],r['mode']];assert (r['outputBytes'],r['fnv1aChecksum'])==(len(payload),checksum(payload,1 if validation else 3500))
  if validation:assert r['validated'];continue
  assert (r['samples'],r['warmupSamples'],r['repetitionsPerSample'])==(25,10,100)
  for clock in ['wall','cpu']:
   values=r[clock+'SampleNanoseconds'];assert len(values)==25 and all((v>=0 if clock=='cpu' else v>0) and v<float('inf') for v in values)
   s=sorted(values);assert s[12]>0 and (r[clock+'MedianNanoseconds'],r[clock+'P95Nanoseconds'])==(s[12],s[23])
   rows[r['name'],r['mode']+'-'+clock]={'name':r['name'],'mode':r['mode']+'-'+clock,'medianNanoseconds':s[12],**{k:r[k] for k in ['outputBytes','fnv1aChecksum','samples','warmupSamples','repetitionsPerSample']}}
  assert r['cpuZeroSamples']==sum(v==0 for v in r['cpuSampleNanoseconds'])
 return rows
