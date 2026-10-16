#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Bind native qualification of a Git-free export to its inspected source archive."""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile


def manifest(root, archive, revision, sources, paths):
    if not revision['clean']:
        raise RuntimeError('Archive provenance requires a clean Git producer')
    return {'schemaVersion': 1, 'origin': 'source-archive',
            'commit': revision['commit'], 'tree': revision['tree'],
            'archivePath': str(archive.resolve()),
            'archiveSHA256': hashlib.sha256(archive.read_bytes()).hexdigest(),
            'sources': sources,
            'inventory': [{'path': p, 'sha256': hashlib.sha256((root / p).read_bytes()).hexdigest()}
                          for p in sorted(paths)]}


def revision(root, provenance, sources):
    root, provenance = root.resolve(), provenance.resolve()
    if (root / '.git').exists() or (root / '.git').is_symlink():
        raise RuntimeError('Archive provenance cannot replace checkout Git identity')
    if provenance.is_relative_to(root):
        raise RuntimeError('Archive provenance must be outside the exported source')
    encoded = provenance.read_bytes()
    value = json.loads(encoded)
    keys = {'schemaVersion', 'origin', 'commit', 'tree', 'archivePath',
            'archiveSHA256', 'sources', 'inventory'}
    if set(value) != keys or value['schemaVersion'] != 1 or value['origin'] != 'source-archive':
        raise RuntimeError('Unrecognized archive provenance')
    if any(not isinstance(value[k], str) or not re.fullmatch(r'[0-9a-f]{40}', value[k])
           for k in ['commit', 'tree']):
        raise RuntimeError('Invalid producer revision')
    if value['sources'] != sources:
        raise RuntimeError('Exported source snapshot differs from its producer')
    inventory = {}
    for item in value['inventory']:
        name = item['path']; path = PurePosixPath(name)
        if (set(item) != {'path', 'sha256'} or path.is_absolute() or '..' in path.parts
                or path.as_posix() != name or name in inventory
                or any(p in {'.git', '.build', 'Artifacts', '.env', '.swiftpm', '.codex'} for p in path.parts)
                or not re.fullmatch(r'[0-9a-f]{64}', item['sha256'])):
            raise RuntimeError('Invalid or duplicate archive inventory path')
        inventory[name] = item['sha256']
    if not inventory:
        raise RuntimeError('Empty source archive inventory')
    archive = Path(value['archivePath']).resolve()
    if archive.is_relative_to(root):
        raise RuntimeError('Producer archive must be outside the exported source')
    raw = archive.read_bytes()
    if hashlib.sha256(raw).hexdigest() != value['archiveSHA256']:
        raise RuntimeError('Producer source archive checksum differs')
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as package:
        if package.pax_headers.get('comment') != value['commit']:
            raise RuntimeError('Git archive commit differs from its producer')
        for member in package.getmembers():
            path = PurePosixPath(member.name)
            if (path.is_absolute() or '..' in path.parts or member.issym() or member.islnk()
                    or not (member.isdir() or member.isfile())):
                raise RuntimeError('Unsafe source archive entry')
            if member.isdir():
                continue
            if member.name not in inventory or member.name in seen:
                raise RuntimeError('Source archive inventory differs')
            data = package.extractfile(member).read()
            target = root / member.name
            if (any((root / Path(*path.parts[:i])).is_symlink() for i in range(1, len(path.parts) + 1))
                    or not target.is_file() or target.read_bytes() != data
                    or stat.S_IMODE(target.stat().st_mode) != (member.mode & 0o777)
                    or hashlib.sha256(data).hexdigest() != inventory[member.name]):
                raise RuntimeError('Exported file differs from the source archive: ' + member.name)
            seen.add(member.name)
    if seen != set(inventory):
        raise RuntimeError('Missing source archive files')
    return {'commit': value['commit'], 'tree': value['tree'], 'clean': True,
            'origin': 'source-archive', 'archiveSHA256': value['archiveSHA256'],
            'provenanceSHA256': hashlib.sha256(encoded).hexdigest()}
