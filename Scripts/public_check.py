#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check fixture integrity, attribution and package boundaries without building."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
pins = json.loads((ROOT / 'Documentation/ConformancePins.json').read_text())
fixture = ROOT / pins['goldenLiquid']['path']
assert hashlib.sha256(fixture.read_bytes()).hexdigest() == pins['goldenLiquid']['sha256'], 'Fixture hash changed'
cases = json.loads(fixture.read_text())['tests']
assert len(cases) == pins['goldenLiquid']['cases'] == 1098, 'Fixture count changed'
assert len({case['name'] for case in cases}) == len(cases), 'Duplicate fixture names'
probe_pin = pins['authoredProbes']
probes = ROOT / probe_pin['path']
assert hashlib.sha256(probes.read_bytes()).hexdigest() == probe_pin['sha256'], 'Probe hash changed'
probe_cases = json.loads(probes.read_text())['tests']
assert len(probe_cases) == probe_pin['cases'] == 221, 'Probe count changed'
assert len({case['name'] for case in probe_cases}) == len(probe_cases), 'Duplicate probe names'
for pin, count in [(pins['recoveredErrors'], 1), (pins['rubyDate']['grammarCases'], 337), (pins['dateFilters'], 376)]:
    path = ROOT / pin['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == pin['sha256'], f"Pinned data changed: {path}"
    records = json.loads(path.read_text())['tests']
    assert len(records) == pin['cases'] == count, f"Pinned count changed: {path}"
    if isinstance(records, list):
        assert len({case['name'] for case in records}) == count, 'Duplicate date case names'
source_pin = pins['rubyDate']['source']
assert hashlib.sha256((ROOT / source_pin['path']).read_bytes()).hexdigest() == source_pin['sha256'], 'Upstream date source changed'
assert 'Redistribution and use' in (ROOT / 'Licenses/RubyDate/BSDL').read_text(), 'Missing Ruby BSD terms'
assert 'MIT License' in (fixture.parent / 'LICENSE').read_text(), 'Missing corpus license'
manifest = (ROOT / 'Package.swift').read_text()
assert 'dependencies: []' in manifest, 'Root dependency graph must be empty'
assert '.library(name: "Liquid"' in manifest and '.executable(name: "liquid"' in manifest
for path in (ROOT / 'Sources').rglob('*.swift'):
    source = path.read_text()
    assert '@unchecked' not in source, f'Unchecked concurrency: {path}'
    assert 'SPDX-License-Identifier: Apache-2.0' in source, f'Missing license: {path}'
print(f'Public checks passed; {len(cases)} intact independent fixtures and {len(probe_cases)} authored probes.')
