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
from ci import ROOT, environment, source_revision, source_snapshot
from archive_provenance import manifest, revision as archive_revision
from documentation_transport import ARCHIVE, DESCRIPTOR, admit_site, strict_json

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
    tar = subprocess.check_output(['git', '-c', 'tar.umask=0022', 'archive', '--format=tar', 'HEAD'], cwd=ROOT)
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
    provenance = Path(temporary) / 'source-provenance.json'
    descriptor = manifest(ROOT, output / name, source_revision(), source_snapshot(), paths)
    provenance.write_text(json.dumps(descriptor, indent=2) + '\n')
    shutil.copyfile(provenance, output / 'clean-source-provenance.json')
    expected_revision = archive_revision(clean, provenance, descriptor['sources'])
    result = subprocess.run([sys.executable, '-B', 'Scripts/ci.py', '--lane', 'native',
                             '--archive-provenance', str(provenance)],
                            cwd=clean, env=env, capture_output=True, text=True)
    (output / 'clean-native.log').write_text(result.stdout + result.stderr)
    if (clean / 'Artifacts/native').exists():
        shutil.copytree(clean / 'Artifacts/native', output / 'clean-native', dirs_exist_ok=True)
    if result.returncode:
        raise RuntimeError('Clean source archive qualification failed; see clean-native.log')
    native_path = clean / 'Artifacts/native/receipt.json'
    native = json.loads(native_path.read_text())
    if (native['status'] != 'passed' or not native['sourceQualified'] or not native['sourceUnchanged']
            or native['sources'] != descriptor['sources']
            or native['sourceRevision'] != expected_revision or native['endingSourceRevision'] != expected_revision):
        raise RuntimeError('Clean native receipt differs from its inspected archive provenance')
    native_receipt_sha = hashlib.sha256(native_path.read_bytes()).hexdigest()

assets = {name: hashlib.sha256(first).hexdigest()}
docs = ROOT / 'Artifacts/docs/Liquid.doccarchive.tar.gz'
if not docs.exists():
    raise RuntimeError('Compile documentation before preparing release assets')
docs_root = docs.parent
docs_receipt = strict_json((docs_root / 'receipt.json').read_bytes())
if (docs_receipt.get('lane') != 'docs' or docs_receipt.get('status') != 'passed'
        or docs_receipt.get('sourceQualified') is not True or docs_receipt.get('sourceUnchanged') is not True
        or docs_receipt.get('sourceRevision') != source_revision()
        or docs_receipt.get('endingSourceRevision') != source_revision()
        or docs_receipt.get('sources') != source_snapshot()):
    raise RuntimeError('Documentation input differs from clean archive producer source')
site_body = (docs_root / 'site.json').read_bytes()
transport_body = (docs_root / DESCRIPTOR).read_bytes()
site = admit_site((docs_root / ARCHIVE).read_bytes(), strict_json(transport_body), site_body)
site_manifest = strict_json(site_body)
site_info = site_manifest.get('buildInformation', {})
run_id = env.get('GITHUB_RUN_ID', '')
expected_run_url = 'https://github.com/ThorFuchs/Swift-Liquid/actions/runs/' + run_id if run_id.isdigit() else None
if (site_manifest.get('status') != 'passed' or site_manifest.get('basePath') != '/Swift-Liquid'
        or site_info.get('sourceCommit') != commit or site_info.get('sourceState') != 'clean'
        or site_info.get('documentationTracks') != 'main' or site_info.get('runURL') != expected_run_url
        or site_info.get('sourceInventorySHA256') != hashlib.sha256(
            json.dumps(docs_receipt['sources'], sort_keys=True).encode()).hexdigest()
        or strict_json(site.files['build-info.json']) != site_info):
    raise RuntimeError('Documentation site provenance differs from clean archive producer')
shutil.copyfile(docs, output / docs.name)
assets[docs.name] = hashlib.sha256(docs.read_bytes()).hexdigest()
(output / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in sorted(assets.items())))
receipt = {'candidateCommit': commit, 'trackedFileCount': len(paths), 'inventory': paths,
           'documentationTransportSHA256': hashlib.sha256(transport_body).hexdigest(),
           'documentationSiteArchiveSHA256': hashlib.sha256((docs_root / ARCHIVE).read_bytes()).hexdigest(),
           'documentationSiteFiles': len(site.files),
           'byteIdenticalRepeatedSourceArchives': True, 'cleanNativeQualification': 'passed',
           'cleanNativeSourceRevision': expected_revision, 'cleanNativeReceiptSHA256': native_receipt_sha,
           'cleanSourceProvenanceSHA256': expected_revision['provenanceSHA256'], 'assets': assets}
(output / 'archive.json').write_text(json.dumps(receipt, indent=2) + '\n')
print(json.dumps({key: value for key, value in receipt.items() if key != 'inventory'}, indent=2))
