#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compile the public library for each declared Apple simulator platform."""
import json
from pathlib import Path
import subprocess
import sys
from ci import ROOT, environment, swift

env = environment()
output = ROOT / 'Artifacts/platforms'
output.mkdir(parents=True, exist_ok=True)
records = []
if sys.platform != 'darwin':
    raise RuntimeError('Apple SDK qualification requires macOS with Xcode')
for sdk, triple in [('iphonesimulator', 'arm64-apple-ios17.0-simulator'),
                    ('appletvsimulator', 'arm64-apple-tvos17.0-simulator'),
                    ('watchsimulator', 'arm64-apple-watchos10.0-simulator'),
                    ('xrsimulator', 'arm64-apple-xros1.0-simulator')]:
    sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], env=env, text=True).strip()
    version = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-version'], env=env, text=True).strip()
    command = swift() + ['build', '--target', 'Liquid', '--triple', triple, '--sdk', sdk_path,
                         '--scratch-path', str(ROOT / '.build/platforms' / sdk), '-Xswiftc', '-warnings-as-errors']
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    (output / (sdk + '.log')).write_text(result.stdout + result.stderr)
    records.append({'sdk': sdk, 'version': version, 'triple': triple, 'command': command,
                    'exitCode': result.returncode, 'qualification': 'compile-only'})
    (output / 'platforms.json').write_text(json.dumps(records, indent=2) + '\n')
    if result.returncode:
        raise RuntimeError(f'{sdk} failed; see {output / (sdk + ".log")}')
print(json.dumps(records, indent=2))
