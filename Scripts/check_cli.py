#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Exercise externally observable CLI behavior and output-file failure atomicity."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1]).resolve())
cases = 0
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    template = root / 'greeting.liquid'
    template.write_text('Hello, {{ name | upcase }}!')
    data = root / 'context.json'
    data.write_text('{"name":"Ada"}')
    partials = root / 'partials'
    partials.mkdir()
    (partials / 'card.liquid').write_text('<p>{{ name | escape }}</p>')

    def run(args, expected=None, input=None, succeeds=True):
        global cases
        result = subprocess.run([binary] + args, input=input, capture_output=True, text=True)
        assert (result.returncode == 0) == succeeds, (args, result.stderr)
        if expected is not None:
            assert result.stdout == expected, (args, result.stdout, expected)
        if succeeds:
            assert not result.stderr, (args, result.stderr)
        else:
            assert result.stderr.startswith('liquid:'), result.stderr
        cases += 1
        return result

    run(['render', str(template), '--data', str(data)], 'Hello, ADA!')
    run(['render', '-', '--data', str(data)], 'Ada', input='{{ name }}')
    template.write_text("{% render 'card', name: name %}")
    run(['render', str(template), '--data', str(data), '--partials', str(partials)], '<p>Ada</p>')
    run(['validate', str(template)], 'Valid Liquid template.\n')
    destination = root / 'output.html'
    run(['render', str(template), '--data', str(data), '--partials', str(partials), '--output', str(destination)], '')
    assert destination.read_text() == '<p>Ada</p>'
    template.write_text('{% if %}')
    run(['render', str(template), '--output', str(destination)], succeeds=False)
    assert destination.read_text() == '<p>Ada</p>'
    run(['validate', str(template)], succeeds=False)
    run(['render', str(template), '--unknown'], succeeds=False)
    run(['render', str(template), '--data'], succeeds=False)
    run(['render', str(template), '--syntax-mode', 'invalid'], succeeds=False)
    template.write_text('{{ name }}')
    data.write_text('[]')
    run(['render', str(template), '--data', str(data)], succeeds=False)
    data.write_text('{"name":1,"name":2}')
    run(['render', str(template), '--data', str(data)], succeeds=False)
    run(['--version'], 'Swift-Liquid 1.0.0\n')
    run(['--help'])
    source = "{% raw %}{{ hidden | ignored }}{% endraw %}{{ user[key] | host | escape }}{% render 'folder/card' %}{% include selected %}"
    template.write_text(source)
    expected_summary = {'schemaVersion': 1, 'variableRoots': ['key', 'selected', 'user'],
                        'filterNames': ['escape', 'host'], 'literalPartialNames': ['folder/card'],
                        'hasDynamicPartials': True}
    first = run(['analyze', str(template), '--format', 'json'])
    assert json.loads(first.stdout) == expected_summary
    assert first.stdout.endswith('\n')
    second = run(['analyze', '-', '--syntax-mode', 'strict2', '--format', 'json'], input=source)
    assert second.stdout == first.stdout, 'Source path or parser mode changed JSON bytes'
    run(['analyze', str(template)], 'Variable roots: ["key","selected","user"]\nFilter names: ["escape","host"]\nLiteral partial names: ["folder/card"]\nDynamic partial references: yes\n')
    empty = run(['analyze', '-', '--format', 'json'], input='')
    assert json.loads(empty.stdout) == dict(expected_summary, variableRoots=[], filterNames=[],
                                           literalPartialNames=[], hasDynamicPartials=False)
    scalar_source = "{{ café | café }}{{ cafe\u0301 | cafe\u0301 }}{% include 'café' %}{% include 'cafe\u0301' %}"
    scalar = json.loads(run(['analyze', '-', '--format', 'json'], input=scalar_source).stdout)
    for field in ['variableRoots', 'filterNames', 'literalPartialNames']:
        assert scalar[field] == ['cafe\u0301', 'café']
    run(['analyze', '-', '--format', 'json'], input='{% if %}', expected='', succeeds=False)
    run(['analyze', '-', '--syntax-mode', 'strict'], input='{{ name trailing }}', expected='', succeeds=False)
    run(['analyze', '-', '--format', 'xml'], input='', expected='', succeeds=False)
    run(['analyze', str(root / 'absent')], expected='', succeeds=False)
    for options in [['--data', str(data)], ['--partials', str(partials)], ['--output', str(destination)],
                    ['--strict-filters'], ['--format', 'json', '--format', 'text'], ['--format']]:
        run(['analyze', str(template)] + options, expected='', succeeds=False)
    assert destination.read_text() == '<p>Ada</p>'
    run(['render', str(template), '--format', 'json'], expected='', succeeds=False)
    run(['validate', str(template), '--format', 'json'], expected='', succeeds=False)
    template.write_bytes(b'\xff')
    run(['analyze', str(template)], expected='', succeeds=False)
    template.write_text('x' * 1_048_577)
    run(['analyze', str(template)], expected='', succeeds=False)
print(f'{cases} CLI behavior cases passed.')
