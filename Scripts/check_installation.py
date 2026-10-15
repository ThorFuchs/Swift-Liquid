#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Qualify the immutable published compatibility anchor through real public URLs."""
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import tempfile
from ci import ROOT, environment, swift

URL = 'https://github.com/ThorFuchs/Swift-Liquid.git'
VERSION = '1.3.0'
REVISION = '9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e'
OUTPUT = ROOT / 'Artifacts/installation'
OUTPUT.mkdir(parents=True, exist_ok=True)
receipt = {'schemaVersion': 1, 'status': 'failed', 'repository': URL, 'version': VERSION,
           'expectedRevision': REVISION, 'commands': []}

try:
    with tempfile.TemporaryDirectory(prefix='swift-liquid-install-') as directory:
        workspace = Path(directory)
        env = environment()
        env.update(GIT_TERMINAL_PROMPT='0', GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                   CLANG_MODULE_CACHE_PATH=str(workspace / 'modules'),
                   SWIFTPM_MODULECACHE_OVERRIDE=str(workspace / 'modules'))
        (workspace / 'modules').mkdir()

        def run(command, name, cwd=workspace, flags=True):
            if command[:len(swift())] == swift() and flags:
                position = len(swift()) + 1
                options = shlex.split(env.get('LIQUID_SWIFTPM_FLAGS', ''))
                command = command[:position] + options + command[position:]
            result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
            (OUTPUT / (name + '.log')).write_text(result.stdout + result.stderr)
            receipt['commands'].append({'name': name, 'command': command, 'exitCode': result.returncode})
            if result.returncode:
                raise RuntimeError(f'{name} failed; inspect its retained log')
            return result.stdout

        checkout = workspace / 'checkout'
        run(['git', 'clone', '--branch', VERSION, '--depth', '1', URL, str(checkout)], 'clone')
        revision = run(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], 'revision').strip()
        if revision != REVISION:
            raise RuntimeError('Published tag does not resolve to the recorded immutable commit')
        receipt['resolvedRevision'] = revision
        common = ['--package-path', str(checkout), '--scratch-path', str(workspace / 'cli-build'),
                  '--cache-path', str(workspace / 'cache'), '--config-path', str(workspace / 'config'),
                  '--security-path', str(workspace / 'security')]
        manifest = json.loads(run(swift() + ['package', *common, 'dump-package'], 'manifest'))
        if manifest['dependencies'] != [] or {item['name'] for item in manifest['products']} != {'Liquid', 'liquid'}:
            raise RuntimeError('Published package product/dependency boundary changed')
        (OUTPUT / 'published-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        run(swift() + ['build', *common, '-c', 'release', '--product', 'liquid', '-Xswiftc', '-warnings-as-errors'], 'cli-build')
        binary = Path(run(swift() + ['build', *common, '-c', 'release', '--show-bin-path'], 'binary-path').strip().splitlines()[-1]) / 'liquid'
        if run([str(binary), '--version'], 'cli-version').strip() != 'Swift-Liquid ' + VERSION:
            raise RuntimeError('Published CLI version differs')
        template = workspace / 'greeting.liquid'; template.write_text('Hello, {{ name | upcase }}!\n')
        context = workspace / 'context.json'; context.write_text('{"name":"Swift"}\n')
        rendered = run([str(binary), 'render', str(template), '--data', str(context)], 'cli-render')
        if rendered != 'Hello, SWIFT!\n':
            raise RuntimeError('Fresh release CLI output differs')
        run([str(binary), 'validate', str(template)], 'cli-validate')
        receipt['renderedUTF8SHA256'] = hashlib.sha256(rendered.encode()).hexdigest()

        consumer = workspace / 'consumer'
        (consumer / 'Sources/InstalledConsumer').mkdir(parents=True)
        (consumer / 'Package.swift').write_text(f'''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "InstalledConsumer", platforms: [.macOS(.v14)],
    dependencies: [.package(url: "{URL}", exact: "{VERSION}")],
    targets: [.executableTarget(name: "InstalledConsumer", dependencies: [
        .product(name: "Liquid", package: "swift-liquid")
    ])], swiftLanguageModes: [.v6])
''')
        source = (ROOT / 'Examples/Consumer/Sources/LiquidConsumer/main.swift').read_bytes()
        (consumer / 'Sources/InstalledConsumer/main.swift').write_bytes(source)
        receipt['publicConsumerSHA256'] = hashlib.sha256(source).hexdigest()
        resolved = run(swift() + ['run', '--package-path', str(consumer),
            '--cache-path', str(workspace / 'consumer-cache'), '--config-path', str(workspace / 'consumer-config'),
            '--security-path', str(workspace / 'consumer-security'), 'InstalledConsumer'], 'url-consumer')
        if resolved != 'Public consumer examples passed.\n':
            raise RuntimeError('Fresh repository-URL consumer did not complete its public assertions')
        pins = json.loads((consumer / 'Package.resolved').read_text())
        if len(pins['pins']) != 1 or pins['pins'][0]['state'] != {'revision': REVISION, 'version': VERSION}:
            raise RuntimeError('URL consumer resolved an unexpected revision or additional dependency')
        (OUTPUT / 'Package.resolved').write_text(json.dumps(pins, indent=2) + '\n')
        receipt.update(status='passed', products=['Liquid', 'liquid'], transitivePackages=0,
                       cleanSourceAndScratch=True, runtimeQualification='macOS only')
except (OSError, RuntimeError, ValueError, KeyError) as error:
    receipt['error'] = str(error)
(OUTPUT / 'installation.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: value for key, value in receipt.items() if key != 'commands'}, indent=2))
raise SystemExit(0 if receipt['status'] == 'passed' else 1)
