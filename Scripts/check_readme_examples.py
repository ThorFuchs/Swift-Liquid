#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compile the README's exact Swift fences and verify their documented stdout."""
import subprocess
import shlex
from ci import ROOT, environment, swift
from documentation_catalog import EXAMPLE, readme_examples

source, count, expected = readme_examples((ROOT / 'README.md').read_text())
if (ROOT / EXAMPLE).read_text() != source:
    raise RuntimeError('README examples are stale; run python3 -B Scripts/documentation_catalog.py --write-readme-examples')
env = environment()
command = swift() + ['run', '--package-path', 'Examples/READMEConsumer', 'LiquidREADMEConsumer'] + shlex.split(env.get('LIQUID_SWIFTPM_FLAGS', ''))
result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
if result.returncode:
    raise RuntimeError('README consumer failed: ' + result.stderr[-4000:])
if result.stdout != expected:
    raise RuntimeError(f'README stdout differs: expected {expected!r}, received {result.stdout!r}')
print(f'All {count} exact README Swift examples compiled and produced their documented output.')
