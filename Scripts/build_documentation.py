#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compile native public symbol graphs and a static DocC site without plugins."""
import json
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
from ci import ROOT, environment, swift

env = environment()
output = ROOT / 'Artifacts/docs'
output.mkdir(parents=True, exist_ok=True)

def run(command, name):
    if command[:len(swift())] == swift():
        flags = shlex.split(env.get("LIQUID_SWIFTPM_FLAGS", ""))
        position = len(swift()) + 1 if command[len(swift())] == "package" else len(command)
        command = command[:position] + flags + command[position:]
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    (output / (name + '.log')).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'{name} failed: {result.stderr[-2000:]}')

run(swift() + ['package', 'dump-symbol-graph', '--minimum-access-level', 'public'], 'symbols')
candidates = list((ROOT / '.build').rglob('Liquid.symbols.json'))
if not candidates:
    raise RuntimeError('No public Liquid symbol graph was generated')
graph = max(candidates, key=lambda p: p.stat().st_mtime)
graphs = output / 'symbols'
graphs.mkdir(exist_ok=True)
shutil.copyfile(graph, graphs / graph.name)
symbols = json.loads(graph.read_text())['symbols']
if not symbols:
    raise RuntimeError('Empty public API symbol graph')
tool = ['xcrun', 'docc'] if sys.platform == 'darwin' else ['docc']
archive = output / 'Liquid.doccarchive'
run(tool + ['convert', str(ROOT / 'Sources/Liquid/Documentation.docc'),
            '--additional-symbol-graph-dir', str(graphs), '--output-dir', str(archive),
            '--fallback-bundle-identifier', 'org.swift-liquid.Liquid',
            '--transform-for-static-hosting', '--hosting-base-path', 'Swift-Liquid',
            '--warnings-as-errors'], 'docc')
(archive / '.nojekyll').write_text('')
run(swift() + ['run', '--package-path', 'Examples/Consumer', 'LiquidConsumer'], 'consumer')
print(f'DocC compiled with {len(symbols)} public symbols: {archive}')
