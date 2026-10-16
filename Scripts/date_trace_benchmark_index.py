# SPDX-License-Identifier: Apache-2.0
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
