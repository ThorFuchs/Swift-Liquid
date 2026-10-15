#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Opt-in independent functional conformance gate; never runs timing suites."""
import argparse
import datetime
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
from ci import ROOT, environment, swift, source_snapshot

PINS = {'spec': '84bf25e0edbca5f7e530574788b0f875ab331f50', 'ruby': '4e39ae4cc3da73921923c0669e0fc84a66b2f696'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--spec-path', type=Path, required=True)
    parser.add_argument('--reference-path', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'Artifacts/liquid-spec')
    args = parser.parse_args()
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    prior = [path for path in output.iterdir() if path.name != 'history']
    if prior:
        history = output / 'history' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        history.mkdir(parents=True)
        for path in prior:
            shutil.move(str(path), history / path.name)
    env = environment(); env['TZ'] = 'UTC'
    ruby = os.environ.get('LIQUID_RUBY') or shutil.which('ruby')
    if not ruby:
        raise RuntimeError('Set LIQUID_RUBY to a supported Ruby executable')
    receipt = {'rubyExecutable': ruby, 'status': 'failed', 'pins': PINS, 'sources': source_snapshot(), 'commands': [], 'scope': 'functional-only'}

    def run(command, name, check=True):
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
        (output / (name + '.log')).write_text(result.stdout + result.stderr)
        receipt['commands'].append({'command': command, 'exitCode': result.returncode, 'log': name + '.log'})
        if check and result.returncode:
            raise RuntimeError(name + ' failed')
        return result

    try:
        for key, path in [('spec', args.spec_path), ('ruby', args.reference_path)]:
            actual = run(['git', '-C', str(path), 'rev-parse', 'HEAD'], key + '-pin').stdout.strip()
            clean = run(['git', '-C', str(path), 'status', '--porcelain'], key + '-clean').stdout.strip()
            if actual != PINS[key] or clean:
                raise RuntimeError('Wrong or dirty upstream ' + key)
        receipt['swift'] = run(swift() + ['--version'], 'swift-version').stdout.strip()
        receipt['ruby'] = run([ruby, '--version'], 'ruby-version').stdout.strip()
        run(swift() + ['build', '-c', 'release', '--package-path', 'Tools/LiquidSpecAdapter', '-Xswiftc', '-warnings-as-errors'], 'adapter-build')
        binary_dir = run(swift() + ['build', '-c', 'release', '--package-path', 'Tools/LiquidSpecAdapter', '--show-bin-path'], 'adapter-location').stdout.strip().splitlines()[-1]
        binary = str(Path(binary_dir) / 'LiquidSpecJSONRPC')
        receipt['binarySHA256'] = hashlib.sha256(Path(binary).read_bytes()).hexdigest()
        run([sys.executable, '-B', 'Scripts/check_liquid_spec_protocol.py', binary], 'protocol-tests')
        run([ruby, '-I', str(args.spec_path.resolve() / 'lib'), 'Tools/LiquidSpecAdapter/check_bridge.rb'], 'bridge-tests')
        command = [ruby, '-I', str(args.reference_path.resolve() / 'lib'), '-I', str(args.spec_path.resolve() / 'lib'),
                   'Tools/LiquidSpecAdapter/run.rb', '--binary', binary, '--output', str(output / 'spec')]
        result = run(command, 'liquid-spec-runner', check=False)
        receipt['runnerExitCode'] = result.returncode
        runs = json.loads((output / 'spec/SPEC_RUNS.json').read_text())
        matrix = json.loads((output / 'spec/ELIGIBILITY_MATRIX.json').read_text())
        if len(matrix) != runs['observedRows'] or sum(s['expandedVariants'] for s in runs['suites']) != len(matrix):
            raise RuntimeError('Independent suite accounting does not reconcile')
        pins = json.loads((ROOT / 'Tools/LiquidSpecAdapter/Pins.json').read_text())
        for suite in runs['suites']:
            if suite['loadedSourceCases'] != pins['advertisedSourceCounts'][suite['suite']]:
                raise RuntimeError('Pinned suite source counts changed')
        for name in ['ELIGIBILITY_MATRIX.json', 'SPEC_RUNS.json', 'RPC_TRACES.jsonl']:
            receipt.setdefault('reportSHA256', {})[name] = hashlib.sha256((output / 'spec' / name).read_bytes()).hexdigest()
        receipt['specRuns'] = runs['suites']
        receipt['status'] = 'passed' if result.returncode == 0 else 'failed'
        if result.returncode:
            receipt['error'] = 'Independent conformance gate has mismatches or operational errors; see exact matrix'
    except (RuntimeError, OSError, ValueError) as error:
        receipt['error'] = str(error)
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({k: v for k, v in receipt.items() if k not in ['sources', 'commands']}, indent=2))
    return 0 if receipt['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
