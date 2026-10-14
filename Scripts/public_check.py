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
assert len(json.loads(probes.read_text())['tests']) == probe_pin['cases'] == 63, 'Probe count changed'
assert 'MIT License' in (fixture.parent / 'LICENSE').read_text(), 'Missing corpus license'
manifest = (ROOT / 'Package.swift').read_text()
assert 'dependencies: []' in manifest, 'Root dependency graph must be empty'
assert '.library(name: "Liquid"' in manifest and '.executable(name: "liquid"' in manifest
for path in (ROOT / 'Sources').rglob('*.swift'):
    source = path.read_text()
    assert '@unchecked' not in source, f'Unchecked concurrency: {path}'
    assert 'SPDX-License-Identifier: Apache-2.0' in source, f'Missing license: {path}'
print(f'Public checks passed; {len(cases)} intact independent fixtures.')
