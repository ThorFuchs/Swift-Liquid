#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Adapted from Swift-JSON's documentation_catalog.py; Copyright 2026 Thor Fuchs.
"""Qualify authored public comments and the exact executable README examples."""
import argparse
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = Path('Examples/READMEConsumer/Sources/LiquidREADMEConsumer/main.swift')
BASELINE = Path('Documentation/PublicAPI-1.3.0.json')
BASELINE_SHA256 = '09271e97eeae6236ae1059325ec4b9ebffe39d12b4e8d7a2317c44cc90fc09ed'


def public_symbols(graph, root=ROOT):
    data = json.loads(graph.read_text())
    if data.get('module', {}).get('name') != 'Liquid':
        raise ValueError('Expected the Liquid compiler symbol graph')
    symbols = {}
    for symbol in data['symbols']:
        location = symbol.get('location')
        if not location or symbol['kind']['identifier'] == 'swift.extension':
            continue  # Compiler synthesis and extension containers are not authored declarations.
        source = Path(unquote(urlparse(location['uri']).path)).resolve()
        relative = source.relative_to(root.resolve())
        if relative.parts[:2] != ('Sources', 'Liquid') or not source.is_file():
            raise ValueError('Public declaration outside Liquid sources: ' + str(relative))
        if symbol['accessLevel'] != 'public':
            raise ValueError('Non-public declaration in public graph')
        symbols[symbol['identifier']['precise']] = symbol
    if not symbols:
        raise ValueError('No authored public Liquid declarations')
    return sorted(symbols.values(), key=lambda s: s['identifier']['precise'])


def verify_comments(symbols):
    errors = []
    for symbol in symbols:
        text = '\n'.join(line['text'] for line in symbol.get('docComment', {}).get('lines', []))
        label = '.'.join(symbol['pathComponents'])
        if not text.strip() or text.lstrip().startswith('- '):
            errors.append(label + ': missing summary')
        for parameter in symbol.get('functionSignature', {}).get('parameters', []):
            name = parameter.get('internalName', parameter['name'])
            if not re.search(r'^\s*- (?:Parameter )?' + re.escape(name) + r':\s*\S', text, re.M):
                errors.append(label + ': missing parameter ' + name)
    return {'authoredPublicDeclarations': len(symbols), 'errors': errors,
            'policy': 'Summaries and named parameters on every authored public declaration; synthesis and extension containers excluded.'}


def verify_public_baseline(symbols, baseline):
    declarations = baseline.get('declarations', [])
    if not declarations or len({s['identifier'] for s in declarations}) != len(declarations):
        raise ValueError('Empty or duplicate published public API baseline')
    current = {s['identifier']['precise']: ''.join(f['spelling'] for f in s['declarationFragments']) for s in symbols}
    errors = []
    for symbol in declarations:
        label = '.'.join(symbol['path'])
        if symbol['identifier'] not in current:
            errors.append(label + ': published declaration removed')
        elif current[symbol['identifier']] != symbol['declaration']:
            errors.append(label + ': published declaration changed')
    return {'baselineRelease': baseline['release'], 'baselineCommit': baseline['commit'],
            'baselineDeclarations': len(declarations), 'currentDeclarations': len(symbols), 'errors': errors}


def published_baseline():
    raw = (ROOT / BASELINE).read_bytes()
    if hashlib.sha256(raw).hexdigest() != BASELINE_SHA256:
        raise ValueError('Published 1.3.0 API baseline changed')
    return json.loads(raw)


def readme_examples(text):
    blocks = re.findall(r'^```swift\n(.*?)\n```', text, re.M | re.S)
    if len(blocks) < 3 or not blocks[0].startswith('.package(') or not blocks[1].startswith('.product('):
        raise ValueError('Expected two installation fragments followed by standalone Swift examples')
    imports, body, expected = [], [], []
    for block in blocks[2:]:
        lines = block.splitlines()
        if 'import Liquid' not in lines:
            raise ValueError('Every runnable README example must import Liquid')
        before = len(expected)
        imports.extend(line for line in lines if line.startswith('import '))
        code = [line for line in lines if not line.startswith('import ')]
        for line in code:
            if re.match(r'\s*print\(', line):
                match = re.fullmatch(r'\s*print\(.+\)\s+// (.*)', line)
                if not match:
                    raise ValueError('README print statements need explicit expected stdout')
                expected.append(match.group(1))
        if len(expected) == before:
            raise ValueError('Every runnable README example must demonstrate expected output')
        body.append('        do {\n' + '\n'.join('            ' + line if line else '' for line in code).strip('\n') + '\n        }')
    if not expected or 'import Liquid' not in imports:
        raise ValueError('README has no executable Liquid output examples')
    source = '// SPDX-License-Identifier: Apache-2.0\n// Generated from README Swift fences; regenerate with Scripts/documentation_catalog.py.\n'
    source += '\n'.join(dict.fromkeys(imports)) + '\n\n@main\nstruct LiquidREADMEConsumer {\n    static func main() async throws {\n'
    source += '\n\n'.join(body) + '\n    }\n}\n'
    return source, len(blocks) - 2, '\n'.join(expected) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write-readme-examples', action='store_true', required=True)
    parser.parse_args()
    source, count, _ = readme_examples((ROOT / 'README.md').read_text())
    (ROOT / EXAMPLE).write_text(source)
    print(f'Wrote {count} README examples to {EXAMPLE}')
