#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Exercise externally observable CLI behavior and output-file failure atomicity."""
from pathlib import Path
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
print(f'{cases} CLI behavior cases passed.')
