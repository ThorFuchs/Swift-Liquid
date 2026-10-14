#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Produce a deterministic tracked-source archive and qualify a clean extraction."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
from ci import ROOT, environment

env = environment()
output = ROOT / 'Artifacts/archive'
output.mkdir(parents=True, exist_ok=True)
changes = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True)
if changes.strip():
    raise RuntimeError('Archive qualification requires a clean candidate commit')
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).split(b'\0')
paths = [path.decode() for path in tracked if path]
for path in paths:
    parts = Path(path).parts
    if any(part in ['.build', 'Artifacts', '.env', '.DS_Store', '.swiftpm', '.codex'] for part in parts):
        raise RuntimeError(f'Private/generated path in public inventory: {path}')


def archive_bytes():
    tar = subprocess.check_output(['git', 'archive', '--format=tar', 'HEAD'], cwd=ROOT)
    result = io.BytesIO()
    with gzip.GzipFile(fileobj=result, filename='', mode='wb', mtime=0, compresslevel=9) as package:
        package.write(tar)
    return result.getvalue()


first = archive_bytes()
if first != archive_bytes():
    raise RuntimeError('Repeated source archives are not byte-identical')
name = 'Swift-Liquid-source.tar.gz'
(output / name).write_bytes(first)
with tempfile.TemporaryDirectory(prefix='swift-liquid-clean-') as temporary:
    clean = Path(temporary) / 'Swift-Liquid'
    clean.mkdir()
    with tarfile.open(fileobj=io.BytesIO(first), mode='r:gz') as package:
        # Tracked source is inspected before extraction. Reject links and escapes.
        for member in package.getmembers():
            if member.issym() or member.islnk() or Path(member.name).is_absolute() or '..' in Path(member.name).parts:
                raise RuntimeError(f'Unsafe archive entry: {member.name}')
        package.extractall(clean)
    result = subprocess.run([sys.executable, '-B', 'Scripts/ci.py', '--lane', 'native'], cwd=clean, env=env, capture_output=True, text=True)
    (output / 'clean-native.log').write_text(result.stdout + result.stderr)
    if (clean / 'Artifacts/native').exists():
        shutil.copytree(clean / 'Artifacts/native', output / 'clean-native', dirs_exist_ok=True)
    if result.returncode:
        raise RuntimeError('Clean source archive qualification failed; see clean-native.log')

assets = {name: hashlib.sha256(first).hexdigest()}
docs = ROOT / 'Artifacts/docs/Liquid.doccarchive.tar.gz'
if not docs.exists():
    raise RuntimeError('Compile documentation before preparing release assets')
shutil.copyfile(docs, output / docs.name)
assets[docs.name] = hashlib.sha256(docs.read_bytes()).hexdigest()
(output / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(assets.items())))
receipt = {'candidateCommit': commit, 'trackedFileCount': len(paths), 'inventory': paths,
           'byteIdenticalRepeatedSourceArchives': True, 'cleanNativeQualification': 'passed', 'assets': assets}
(output / 'archive.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: value for key, value in receipt.items() if key != 'inventory'}, indent=2))
