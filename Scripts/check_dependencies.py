#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Exercise dependency CLI boundaries and qualify the report schema with Swift-JSON."""
import copy
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
from ci import ROOT, environment, swift

binary = str(Path(sys.argv[1]).resolve())
cases = 0
with tempfile.TemporaryDirectory(prefix='liquid-dependencies-') as directory:
    root = Path(directory)
    partials = root / 'partials'
    partials.mkdir()
    (partials / 'a.liquid').write_text("{% include 'b' %}")
    (partials / 'b.liquid').write_text("{% include 'a' %}{% include 'missing' %}")
    (partials / 'unused.liquid').write_text('{{ invisible }}')
    (partials / '.hidden.liquid').write_text('{% if %}')
    (partials / 'ignored.txt').write_text('{% if %}')
    (root / 'outside.liquid').write_text('{% if %}')
    (partials / 'symlink.liquid').symlink_to(root / 'outside.liquid')
    (partials / 'directory-link').symlink_to(root, target_is_directory=True)
    source = "{{ user | unknown }}{% include 'a' %}{% include selected %}"
    template = root / 'root.liquid'
    template.write_text(source)

    def run(options=(), source=source, succeeds=True, file=False):
        global cases
        command = [binary, 'analyze', str(template) if file else '-', '--dependencies', *options]
        result = subprocess.run(command, input=None if file else source, capture_output=True, text=True)
        assert (result.returncode == 0) == succeeds, (command, result.stderr)
        if succeeds:
            assert not result.stderr, result.stderr
        else:
            assert result.stdout == '' and result.stderr.startswith('liquid:'), result
        cases += 1
        return result.stdout

    options = ['--partials', str(partials), '--format', 'json']
    first = run(options, file=True)
    assert first == run(options), 'File/stdin changed report bytes'
    report = json.loads(first)
    assert report['kind'] == 'liquid.dependencies' and type(report['schemaVersion']) is int and report['schemaVersion'] == 1
    assert [node['id'] for node in report['nodes']] == [{'kind':'root'}, {'kind':'partial','name':'a'}, {'kind':'partial','name':'b'}]
    assert [edge['requestedName'] for edge in report['edges']] == ['a', 'b', 'a', 'missing']
    assert report['missingReferences'] == [{'origin':{'kind':'partial','name':'b'},'requestedName':'missing','resolvedName':None}]
    assert report['dynamicReferences'] == [{'kind':'root'}]
    assert report['cycles'] == [[{'kind':'partial','name':'a'},{'kind':'partial','name':'b'}]]
    assert str(root) not in first
    # Discovery order must not affect an accepted bundle's bytes.
    for name in ['b', 'a', 'unused']:
        path = partials / (name + '.liquid')
        text = path.read_text(); path.unlink(); path.write_text(text)
    assert run(options) == first
    assert run(['--partials', str(partials)]).startswith('Partial dependencies:\nNode: {"kind":"root"}\n')
    empty = json.loads(run(['--format','json'], source=''))
    assert len(empty['nodes']) == 1 and not empty['edges'] and not empty['cycles']
    missing = json.loads(run(['--format','json'], source="{% include 'absent' %}"))
    assert missing['edges'][0]['resolvedName'] is None
    scalar = json.loads(run(['--format','json'], source="{% include 'café' %}{% include 'cafe\u0301' %}"))
    assert [edge['requestedName'] for edge in scalar['edges']] == ['cafe\u0301','café']
    nested = partials / 'folder'; nested.mkdir()
    (nested / 'card.liquid').write_text('')
    nested_report = json.loads(run(options, source="{% include 'folder/card' %}"))
    assert nested_report['edges'][0]['resolvedName'] == 'folder/card'
    (partials / 'unused.liquid').write_text('{% if %}')
    run(options, succeeds=False)
    (partials / 'unused.liquid').write_text('x' * 1_048_576)
    run(options, source='x', succeeds=False)  # Root plus partials share one source capacity.
    (partials / 'unused.liquid').write_text('')
    for args in [['--data','context.json'], ['--metrics','metrics.json'], ['--output','out'], ['--strict-filters'],
                 ['--dependencies'], ['--format','xml'], ['--partials',str(root/'absent')]]:
        run(args, succeeds=False)
    run(source='{% render selected %}', succeeds=False)
    run(['--syntax-mode','strict2'], source='{{ name trailing }}', succeeds=False)
    run(source='x' * 1_048_577, succeeds=False)
    for command in ['render','validate']:
        result = subprocess.run([binary,command,str(template),'--dependencies'],capture_output=True,text=True)
        assert result.returncode != 0 and result.stdout == '' and result.stderr.startswith('liquid:')
        cases += 1
    # Zero-source partials still spend template and name capacities before parsing.
    many = root / 'many'; many.mkdir()
    for i in range(4_096): (many / f'{i}.liquid').touch()
    exhausted = subprocess.run([binary,'analyze','-','--dependencies','--partials',str(many)],input='',capture_output=True,text=True)
    assert exhausted.returncode == 1 and exhausted.stdout == '' and 'dependencyTemplates' in exhausted.stderr
    cases += 1
    names = root / 'names'; names.mkdir()
    for i in range(1_400): (names / (f'{i:04d}' + 'x'*190 + '.liquid')).touch()
    exhausted = subprocess.run([binary,'analyze','-','--dependencies','--partials',str(names)],input='',capture_output=True,text=True)
    assert exhausted.returncode == 1 and exhausted.stdout == '' and 'dependencyNameBytes' in exhausted.stderr
    cases += 1
    # Canonical-equivalent paths can coexist only on some filesystems. The loader
    # rejects them if supported; macOS volumes commonly normalize them into one file.
    unicode_dir = root / 'unicode'; unicode_dir.mkdir()
    (unicode_dir / 'café.liquid').touch(); (unicode_dir / 'cafe\u0301.liquid').touch()
    if len(list(unicode_dir.iterdir())) == 2:
        result = subprocess.run([binary,'analyze','-','--dependencies','--partials',str(unicode_dir)],input='',capture_output=True,text=True)
        assert result.returncode != 0 and result.stdout == '' and 'Ambiguous partial keys' in result.stderr
        cases += 1
        print('Canonical duplicate-path rejection exercised.')
    else:
        print('Filesystem normalizes canonical-equivalent paths; duplicate-path CLI case unavailable. API spelling/lookup cases remain exercised.')

    vectors = [(True, report), (True, empty), (True, missing), (True, scalar), (True, nested_report),
               (True, dict(report, futureMetadata={'optional':True}))]
    for field in report:
        changed = copy.deepcopy(report); del changed[field]; vectors.append((False,changed))
    for field, value in [('kind','other'),('schemaVersion',2),('schemaVersion',True),('nodes',[]),('edges',{}),('cycles',[[]]),
                         ('dynamicReferences',[{'kind':'partial'}]),('missingReferences',[dict(report['missingReferences'][0],resolvedName='present')])]:
        vectors.append((False,dict(report,**{field:value})))
    for change in [
        {'id':{'kind':'root','name':'ambiguous'},'inspection':report['nodes'][0]['inspection']},
        {'id':{'kind':'partial','name':None},'inspection':report['nodes'][0]['inspection']},
        {'id':{'kind':'root'},'inspection':dict(report['nodes'][0]['inspection'],hasDynamicPartials='true')},
        {'id':{'kind':'root'},'inspection':dict(report['nodes'][0]['inspection'],variableRoots=[1])}
    ]:
        vectors.append((False,dict(report,nodes=[change])))
    command = swift() + ['run','--package-path','Tools/SchemaQualification',*shlex.split(environment().get('LIQUID_SWIFTPM_FLAGS','')),
                         '-Xswiftc','-warnings-as-errors','LiquidSchemaQualification',str(ROOT/'Documentation/Schemas/dependencies-v1.json')]
    for index, (expected, value) in enumerate(vectors):
        path = root / f'vector-{index}.json'
        path.write_text(json.dumps(value,ensure_ascii=False))
        command += ['valid' if expected else 'invalid',str(path)]
    subprocess.run(command,cwd=ROOT,env=environment(),check=True)
print(f'Dependency CLI: {cases} cases passed; schema semantics are qualified by Swift-JSON, graph semantics by API/CLI regressions.')
