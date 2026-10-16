# SPDX-License-Identifier: Apache-2.0
"""Admit literal parser-stage payloads and retain every clock sample."""
import math,statistics

def payload(value):
 out=bytearray()
 def i(n):out.extend(int(n).to_bytes(8,'little',signed=True))
 def s(v):
  out.append(v is not None)
  if v is not None:b=v.encode();i(len(b));out.extend(b)
 s(value.get('text'));span=value.get('span');out.append(span is not None)
 if span is not None:
  i(len(span))
  for n in span:i(n)
 groups=value.get('groups');out.append(groups is not None)
 if groups is not None:
  i(len(groups))
  for g in groups:s(g)
 f=value.get('fields');out.append(f is not None)
 if f is not None:
  for k in ['year','month','day','ordinal','hour','minute','second']:
   n=f[k];out.append(n is not None)
   if n is not None:i(n)
  s(f['fraction']);s(f['zone']);out.extend([f['completeYear'],f['beforeCommonEra']])
 return bytes(out)
def expectations(config):
 rows={}
 def add(name,stage,v):rows[name,stage]=rows[name,stage+'-audit']=payload(v)
 for r in config['dates']:
  for stage in ['normalize','construct']:add(r['name'],stage,dict(text=r['normalized']))
  if r['fields'] is not None:add(r['name'],'grammar',dict(fields=r['fields']))
 for r in config['matches']:
  add(r['name'],'match',dict(span=r['span']))
  for stage in ['captures','find']:add(r['name'],stage,dict(groups=r['groups']))
  add(r['name'],'take',dict(text=r['remaining'],groups=r['groups']))
 assert len(rows)==100
 return rows
from functools import lru_cache
@lru_cache(None)
def checksum(p,count):
 h=14695981039346656037
 for _ in range(count):
  for b in p:h=((h^b)*1099511628211)&((1<<64)-1)
 return format(h,'x')
def index_components(data,config,caller,order,validation=False):
 assert data['configuration']=='release' and data['caller']==caller and data['recordOrder']==order and data['kind']==('validation' if validation else 'measurement')
 expected=expectations(config);keys=list(expected);keys=keys if order=='forward' else keys[::-1];assert [(r['name'],r['stage']) for r in data['records']]==keys;out={}
 for r in data['records']:
  key=r['name'],r['stage'];p=expected[key];assert (r['outputBytes'],r['fnv1aChecksum'])==(len(p),checksum(p,1 if validation else 17500))
  if validation:assert r['validated'];continue
  assert (r['samples'],r['warmupSamples'],r['repetitionsPerSample'])==(25,10,500)
  for clock in ['wall','cpu']:
   a=r[clock+'SampleNanoseconds'];assert len(a)==25 and all(math.isfinite(x) and (x>=0 if clock=='cpu' else x>0) for x in a);s=sorted(a);assert s[12]>0 and (r[clock+'MedianNanoseconds'],r[clock+'P95Nanoseconds'])==(s[12],s[23])
  assert r['cpuZeroSamples']==sum(x==0 for x in r['cpuSampleNanoseconds']);out[key]=r
 return out
