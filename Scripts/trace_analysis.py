# SPDX-License-Identifier: Apache-2.0
"""Analyze exported instrument observations without treating trace time as a benchmark."""
from collections import Counter,defaultdict
from pathlib import Path
import re
from xml.etree import ElementTree as ET

class Table:
    def __init__(self,path):
        self.root=ET.parse(path).getroot()
        self.ids={e.get('id'):e for e in self.root.iter() if e.get('id')}
        schemas=self.root.findall('.//schema');assert len(schemas)==1,(path,len(schemas))
        self.columns=[c.findtext('mnemonic') for c in schemas[0].findall('col')]
        self.rows=[]
        for row in self.root.findall('.//row'):
            assert len(row)==len(self.columns),(path,len(row),len(self.columns))
            self.rows.append(dict(zip(self.columns,list(row))))
    def node(self,e):
        seen=set()
        while e.get('ref'):
            ref=e.get('ref');assert ref not in seen;seen.add(ref);e=self.ids[ref]
        return e
    def text(self,e):
        e=self.node(e)
        return e.get('fmt') or e.get('name') or (e.text or '').strip()
    def number(self,e):return int(self.node(e).text)
    def pid(self,e):
        e=self.node(e)
        if e.tag=='sentinel':return None
        child=e.find('pid');assert child is not None
        return self.number(child)
    def frames(self,e):
        stack=self.node(e);out=[]
        for item in stack.findall('frame'):
            frame=self.node(item);name=frame.get('name') or '<unresolved>'
            binary=frame.find('binary')
            binary=self.node(binary) if binary is not None else None
            out.append((name,binary.get('name') if binary is not None else '<unknown>'))
        return out

def intervals(path,pid):
    t=Table(path);result={}
    for r in t.rows:
        if t.text(r['name'])!='RenderBatch' or t.text(r['subsystem'])!='org.swift-liquid.date-trace':continue
        start=t.text(r['start-message']);end=t.text(r['end-message'])
        match=re.search(r'case=((?:iso|epoch|filter)-(?:source|reused))',start)
        assert match and match.group(0) in end,(start,end)
        assert t.pid(r['process'])==t.pid(r['end-process'])==pid
        key=match.group(1);assert key not in result
        low=t.number(r['start']);duration=t.number(r['duration']);assert duration>0
        result[key]={'start':low,'end':low+duration,'durationNanoseconds':duration}
    assert set(result)=={n+'-'+m for n in ['iso','epoch','filter'] for m in ['source','reused']}
    ordered=sorted(result.values(),key=lambda r:r['start']);assert all(a['end']<=b['start'] for a,b in zip(ordered,ordered[1:]))
    return result

def cpu(path,regions,pid):
    t=Table(path);result={}
    for key,interval in regions.items():
        symbols=Counter();binaries=Counter();groups=Counter();total=unknown=records=0
        for r in t.rows:
            timestamp=t.number(r['time'])
            if not interval['start']<=timestamp<interval['end'] or t.pid(r['process'])!=pid:continue
            assert t.text(r['thread-state'])=='Running'
            weight=t.number(r['weight']);assert weight>0
            frames=t.frames(r['stack']);records+=1;total+=weight
            leaf,library=frames[0] if frames else ('<unresolved>','<unknown>')
            symbols[leaf]+=weight;binaries[library]+=weight
            if leaf=='<unresolved>' or leaf.startswith('0x'):unknown+=weight
            names=[f[0] for f in frames]
            if any('parseLiquidDate' in x or 'RubyDateParser.' in x for x in names):groups['date-parser-inclusive']+=weight
            if any('renderStrftime' in x or 'LiquidDateParts.' in x for x in names):groups['date-formatter-inclusive']+=weight
            if any('LiquidTemplate.' in x or re.search(r'(^|[^A-Za-z])(Lexer|Parser)\.',x) for x in names):groups['template-parser-inclusive']+=weight
        assert total>0 and records>0,(path,key,'no active CPU samples')
        if key.startswith('iso-'):assert records>=50,(path,key,'fewer than 50 date CPU samples')
        result[key]={'samples':records,'sampleWeightNanoseconds':total,'unresolvedSelfWeightNanoseconds':unknown,
            'selfSymbols':[{'symbol':n,'sampleWeightNanoseconds':v} for n,v in symbols.most_common()],
            'selfBinaries':dict(binaries),'inclusiveGroups':dict(groups)}
    return result

def normalize_executor(value):
    if value.startswith('Main Actor'):return 'Main Actor'
    return value or '<missing>'

def executors(path,regions,pid):
    t=Table(path);result={}
    for key,interval in regions.items():
        states=Counter();running=Counter();runCounts=Counter();resumes=Counter();transitions=Counter();byTask=defaultdict(list);segments=0
        for r in t.rows:
            low=t.number(r['start']);high=low+t.number(r['duration'])
            overlap=min(high,interval['end'])-max(low,interval['start'])
            if overlap<=0 or t.pid(r['process'])!=pid:continue
            state=t.text(r['state']);states[state]+=overlap;segments+=1
            if state=='Running':
                executor=normalize_executor(t.text(r['actor']));running[executor]+=overlap;runCounts[executor]+=1
                resumes[t.text(r['resume-function']) or '<missing>']+=1
                byTask[t.text(r['task'])].append((low,high,executor))
        for segmentsForTask in byTask.values():
            ordered=sorted(segmentsForTask)
            for a,b in zip(ordered,ordered[1:]):
                if a[2]!=b[2]:transitions[a[2]+' -> '+b[2]]+=1
        assert sum(runCounts.values())>0,(path,key,'no task running intervals')
        result[key]={'overlappingStateRows':segments,'stateOccupancyNanoseconds':dict(states),
            'executorRunningNanoseconds':dict(running),'executorRunningIntervals':dict(runCounts),
            'resumeFunctions':dict(resumes),'observedRunningSegmentTransitions':dict(transitions)}
    return result
