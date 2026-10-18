#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compile native public symbol graphs and a static DocC site without plugins."""
import json
import re
from pathlib import Path
import shutil
import shlex
import tarfile
import subprocess
import sys
from ci import ROOT, environment, swift
from documentation_catalog import public_symbols, verify_comments, published_baseline, verify_public_baseline
from build_documentation_site import build_site, prepare_navigation_index
from documentation_transport import ARCHIVE, DESCRIPTOR, pack_site

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
    return result.stdout

run([sys.executable, '-B', 'Scripts/check_documentation_contract.py'], 'documentation-contract')
emitted = run(swift() + ['package', 'dump-symbol-graph', '--minimum-access-level', 'public'], 'symbols')
directories = re.findall(r'^Files written to (.+)$', emitted, re.M)
if len(directories) != 1:
    raise RuntimeError('Swift did not identify one fresh symbol graph directory')
graph = Path(directories[0]).resolve() / 'Liquid.symbols.json'
if (ROOT / '.build').resolve() not in graph.parents or not graph.is_file():
    raise RuntimeError('Fresh Liquid graph is absent or outside this checkout build directory')
graphs = output / 'symbols'
if graphs.exists():
    shutil.rmtree(graphs)
graphs.mkdir(exist_ok=True)
shutil.copyfile(graph, graphs / graph.name)
symbols = json.loads(graph.read_text())['symbols']
authored = public_symbols(graph)
coverage = verify_comments(authored)
compatibility = verify_public_baseline(authored, published_baseline())
(output / 'coverage.json').write_text(json.dumps(coverage, indent=2) + '\n')
(output / 'api-compatibility.json').write_text(json.dumps(compatibility, indent=2) + '\n')
if coverage['errors'] or compatibility['errors']:
    raise RuntimeError('Public documentation or 1.3.0 compatibility failure: ' + repr(coverage['errors'] + compatibility['errors']))
run([sys.executable, '-B', 'Scripts/check_readme_examples.py'], 'readme-examples')
tool = ['xcrun', 'docc'] if sys.platform == 'darwin' else ['docc']
archive = output / 'Liquid.doccarchive'
if archive.exists():
    shutil.rmtree(archive)
run(tool + ['convert', str(ROOT / 'Sources/Liquid/Documentation.docc'),
            '--additional-symbol-graph-dir', str(graphs), '--output-dir', str(archive),
            '--fallback-bundle-identifier', 'org.swift-liquid.Liquid',
            '--transform-for-static-hosting', '--hosting-base-path', 'Swift-Liquid',
            '--warnings-as-errors'], 'docc')
(archive / '.nojekyll').write_text('')
prepare_navigation_index(archive)
toolchain = run(swift() + ['--version'], 'site-toolchain')
site = build_site(archive, output / 'site', toolchain)
(output / 'site.json').write_text(json.dumps(site, indent=2) + '\n')
with tarfile.open(output / 'Liquid.doccarchive.tar.gz', 'w:gz') as package:
    package.add(archive, arcname='Liquid.doccarchive')
run(swift() + ['run', '--package-path', 'Examples/Consumer', 'LiquidConsumer'], 'consumer')
run(swift() + ['run', '--package-path', 'Examples/FiltersConsumer', 'LiquidFiltersConsumer'], 'filters-consumer')
run(swift() + ['run', '--package-path', 'Examples/InspectionConsumer', 'LiquidInspectionConsumer'], 'inspection-consumer')
run(swift() + ['run', '--package-path', 'Examples/MetricsConsumer', 'LiquidMetricsConsumer'], 'metrics-consumer')
run(swift() + ['run', '--package-path', 'Examples/DependencyConsumer', 'LiquidDependencyConsumer'], 'dependency-consumer')
site_body = (output / 'site.json').read_bytes()
site_archive, transport = pack_site(output / 'site', site_body)
(output / ARCHIVE).write_bytes(site_archive)
(output / DESCRIPTOR).write_text(json.dumps(transport, indent=2) + '\n')
print(f'DocC compiled with {len(symbols)} public symbols: {archive}')
