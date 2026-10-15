#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Exercise externally observable CLI behavior and output-file failure atomicity."""
from pathlib import Path
import json
import os
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
    run(['--version'], 'Swift-Liquid 1.2.0\n')
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

    # Metrics are a separate schema and destination; rendering still owns stdout.
    template.write_text("{{ name }}{% render 'card', name: name %}")
    data.write_text('{"name":"é👩‍💻"}')
    metrics = root / 'metrics.json'
    args = ['render', str(template), '--data', str(data), '--partials', str(partials)]
    expected = 'é👩‍💻<p>é👩‍💻</p>'
    run(args + ['--metrics', str(metrics)], expected)
    payload = json.loads(metrics.read_text())
    assert set(payload) == {'schemaVersion', 'totalNanoseconds', 'parseNanoseconds', 'sourceBytes',
                            'outputBytes', 'renderSteps', 'loopIterations', 'admittedValues'}
    assert payload['schemaVersion'] == 1 and payload['parseNanoseconds'] is None
    for key, value in payload.items():
        if key != 'parseNanoseconds':
            assert type(value) is int and value >= 0, (key, value)
    assert payload['outputBytes'] == len(expected.encode())
    assert payload['sourceBytes'] == len(template.read_bytes()) + len((partials / 'card.liquid').read_bytes())
    assert payload['loopIterations'] == 0 and payload['admittedValues'] == 1
    assert metrics.read_bytes().endswith(b'\n')
    run(args + ['--metrics', str(metrics), '--output', str(destination)], '')
    assert destination.read_text() == expected
    run(['render', '-', '--metrics', str(metrics)], '', input='')
    empty_metrics = json.loads(metrics.read_text())
    assert empty_metrics['sourceBytes'] == empty_metrics['outputBytes'] == empty_metrics['admittedValues'] == 0
    run(['render', '-', '--metrics', str(metrics)], 'Z', input='{% capture x %}abcdef{% endcapture %}Z')
    assert json.loads(metrics.read_text())['outputBytes'] == 1

    for options in [['--metrics', '-'], ['--metrics'], ['--metrics', str(metrics), '--metrics', str(metrics)],
                    ['--metrics', str(root)], ['--metrics', str(root / 'missing' / 'metrics.json')],
                    ['--metrics', '/dev/null']]:
        run(args + options, '', succeeds=False)
    for command in ['analyze', 'validate']:
        run([command, str(template), '--metrics', str(metrics)], '', succeeds=False)
    if os.geteuid() != 0:
        readonly = root / 'readonly'
        readonly.mkdir()
        readonly.chmod(0o500)
        try:
            run(args + ['--metrics', str(readonly / 'metrics.json')], '', succeeds=False)
        finally:
            readonly.chmod(0o700)

    protected = [template, data, partials / 'card.liquid', destination]
    for target in protected:
        before = target.read_bytes()
        output = ['--output', str(destination)] if target == destination else []
        run(args + output + ['--metrics', str(target)], '', succeeds=False)
        assert target.read_bytes() == before
    symlink = root / 'input-alias'
    symlink.symlink_to(template)
    run(args + ['--metrics', str(symlink)], '', succeeds=False)
    hardlink = root / 'input-hardlink'
    os.link(data, hardlink)
    run(args + ['--metrics', str(hardlink)], '', succeeds=False)
    dangling = root / 'dangling-metrics'
    dangling.symlink_to(root / 'absent-target')
    run(args + ['--metrics', str(dangling)], '', succeeds=False)
    new_output = root / 'new-output'
    run(args + ['--output', str(new_output), '--metrics', str(root / '.' / 'new-output')], '', succeeds=False)
    parent_link = root / 'parent-link'
    parent_link.symlink_to(root, target_is_directory=True)
    run(args + ['--output', str(new_output), '--metrics', str(parent_link / 'new-output')], '', succeeds=False)
    assert not new_output.exists()

    # Failed rendering/output delivery never replaces a previous metrics document.
    previous = metrics.read_bytes()
    template.write_text('{% if %}')
    run(['render', str(template), '--metrics', str(metrics)], '', succeeds=False)
    assert metrics.read_bytes() == previous
    template.write_text('{{ name | unknown }}')
    run(['render', str(template), '--strict-filters', '--metrics', str(metrics)], '', succeeds=False)
    assert metrics.read_bytes() == previous
    absent_metrics = root / 'absent-metrics.json'
    run(['render', str(template), '--strict-filters', '--metrics', str(absent_metrics)], '', succeeds=False)
    assert not absent_metrics.exists()
    template.write_text('done')
    run(['render', str(template), '--output', str(root), '--metrics', str(metrics)], '', succeeds=False)
    assert metrics.read_bytes() == previous

    # Backpressure holds stdout delivery after destination preflight. Replacing the
    # metrics destination with a directory forces a real late atomic-write failure.
    template.write_text('x' * 200_000)
    late = root / 'late-metrics.json'
    process = subprocess.Popen([binary, 'render', str(template), '--metrics', str(late)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    first_byte = process.stdout.read(1)
    assert first_byte == b'x'
    late.mkdir()
    remaining, error = process.communicate(timeout=15)
    assert process.returncode != 0 and error.startswith(b'liquid:')
    assert first_byte + remaining == b'x' * 200_000
    assert late.is_dir() and not list(late.iterdir())
    cases += 1
print(f'{cases} CLI behavior cases passed.')
