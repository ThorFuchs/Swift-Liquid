# SPDX-License-Identifier: Apache-2.0
import struct
from functools import lru_cache

def word(value):return struct.pack('<q',value)
def optional_word(value):return b'\0' if value is None else b'\1'+word(value)
def optional_string(value):
 if value is None:return b'\0'
 b=value.encode();return b'\1'+word(len(b))+b

def payloads(config):
 rows={}
 for i in config['inputs']:
  name=i['name'];d=i['date'];f=i['fields'];fmt=i['format'];rows[name,'lowercase']=i['lowered'].encode()
  dp=b'\0' if d is None else b'\1'+word(d['seconds'])+word(d['offset'])+word(len(d['fraction'].encode()))+d['fraction'].encode()
  rows[name,'recognition']=rows[name,'recognition-audit']=dp
  if f is not None:
   p=b''.join(optional_word(f[k]) for k in ['year','month','day','ordinal','hour','minute','second'])+optional_string(f['fraction'])+optional_string(f['zone'])+bytes([f['completeYear'],f['beforeCommonEra']]);rows[name,'grammar']=rows[name,'grammar-audit']=p
  if fmt is not None:
   p=fmt['output'].encode()+word(fmt['steps']);rows[name,'format']=rows[name,'format-audit']=p
 assert len(rows)==29;return rows
@lru_cache(None)
def checksum(payload,count):
 h=14695981039346656037
 for _ in range(count):
  for b in payload:h=((h^b)*1099511628211)&((1<<64)-1)
 return format(h,'x')
def index_components(result,config,caller,order,validation=False):
 assert result['configuration']=='release' and result['caller']==caller and result['recordOrder']==order and result['kind']==('validation' if validation else 'measurement')
 expected=payloads(config);keys=list(expected);keys=keys if order=='forward' else keys[::-1];records=result['records'];assert [(r['name'],r['stage']) for r in records]==keys
 for r in records:
  key=r['name'],r['stage'];p=expected[key];assert (r['outputBytes'],r['fnv1aChecksum'])==(len(p),checksum(p,1 if validation else 17500))
  if validation:assert r['validated'];continue
  assert (r['samples'],r['warmupSamples'],r['repetitionsPerSample'])==(25,10,500)
  for clock in ['wall','cpu']:
   times=r[clock+'SampleNanoseconds'];assert len(times)==25 and all((t>=0 if clock=='cpu' else t>0) and t<float('inf') for t in times);ordered=sorted(times);assert ordered[12]>0;assert (r[clock+'MedianNanoseconds'],r[clock+'P95Nanoseconds'])==(ordered[12],ordered[23])
  assert r['cpuZeroSamples']==sum(t==0 for t in r['cpuSampleNanoseconds'])
 return {(r['name'],r['stage']):r for r in records}
