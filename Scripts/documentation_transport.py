# SPDX-License-Identifier: Apache-2.0
"""Preserve a qualified DocC site's names, bytes and modes in a bounded tar envelope.

Importing this module performs no I/O. Colon-bearing Swift declaration names are
valid inside the envelope; only safe ASCII envelope names reach the ZIP uploader.
The envelope is data, never an executable or a substitute for run/source admission.
"""
from dataclasses import dataclass
import gzip
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import tarfile

ARCHIVE = 'site.tar.gz'
DESCRIPTOR = 'site-transport.json'
MAX_MEMBERS = 20000
MAX_SITE_BYTES = 256 * 1024 * 1024
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_TAR_BYTES = MAX_SITE_BYTES + MAX_MEMBERS * 2048 + 10240


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(body):
    return hashlib.sha256(body).hexdigest()


def strict_json(body):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    def constant(_):
        raise ValueError('Nonfinite JSON value')
    return json.loads(body, object_pairs_hook=pairs, parse_constant=constant)


def safe_path(value):
    require(isinstance(value, str) and value and '\\' not in value and '\x00' not in value,
            'Invalid artifact path')
    path = PurePosixPath(value)
    require(not path.is_absolute() and '..' not in path.parts and str(path) == value
            and value != '.' and len(path.parts) <= 128, 'Unsafe or noncanonical artifact path')
    return value


def site_hashes(site_body):
    site = strict_json(site_body)
    require(isinstance(site, dict), 'Invalid site manifest object')
    rows = site.get('files', [])
    require(isinstance(rows, list) and 0 < len(rows) <= MAX_MEMBERS, 'Invalid site inventory size')
    result, folded = {}, set()
    for row in rows:
        require(isinstance(row, dict) and set(row) == {'path', 'sha256'}, 'Invalid site inventory row')
        name = safe_path(row['path'])
        require(name.casefold() not in folded and isinstance(row['sha256'], str)
                and re.fullmatch('[0-9a-f]{64}', row['sha256']), 'Ambiguous site name or digest')
        folded.add(name.casefold()); result[name] = row['sha256']
    return result


@dataclass(frozen=True)
class Site:
    files: dict
    modes: dict


def validate_members(rows):
    require(isinstance(rows, list) and 0 < len(rows) <= MAX_MEMBERS, 'Invalid transport member count')
    result, folded, total = {}, set(), 0
    for row in rows:
        require(isinstance(row, dict), 'Invalid transport member')
        name, kind = row.get('path'), row.get('kind')
        if name != '.':
            safe_path(name)
        require(isinstance(name, str) and name.casefold() not in folded
                and kind in ['file', 'directory'], 'Duplicate, ambiguous or special transport member')
        folded.add(name.casefold())
        require(type(row.get('mode')) is int and 0 <= row['mode'] <= 0o777,
                'Transport modes may not contain special bits')
        keys = {'path', 'kind', 'mode'}
        if kind == 'file':
            keys |= {'bytes', 'sha256'}
            require(name != '.' and type(row.get('bytes')) is int and 0 <= row['bytes'] <= MAX_SITE_BYTES
                    and isinstance(row.get('sha256'), str) and re.fullmatch('[0-9a-f]{64}', row['sha256']),
                    'Invalid transport file size or digest')
            total += row['bytes']
        require(set(row) == keys, 'Unexpected transport member fields')
        result[name] = row
    require(total <= MAX_SITE_BYTES and list(result) == sorted(result), 'Transport size or ordering differs')
    require('.' in result and result['.']['kind'] == 'directory', 'Site root directory missing')
    for name in result:
        if name == '.':
            continue
        parent = str(PurePosixPath(name).parent)
        require(parent in result and result[parent]['kind'] == 'directory', 'Missing directory or file used as parent')
    return result


def pack_site(root, site_body):
    """Return deterministic archive bytes and descriptor without modifying the site."""
    root = Path(root)
    rows, files, total = [], {}, 0
    def visit(path):
        nonlocal total
        info = path.lstat()
        require(not stat.S_ISLNK(info.st_mode), 'Site links cannot enter transport')
        name = str(path.relative_to(root))
        if name != '.':
            safe_path(name)
        row = {'path': name, 'mode': stat.S_IMODE(info.st_mode)}
        require(len(rows) < MAX_MEMBERS, 'Site member count exceeds bound')
        if stat.S_ISDIR(info.st_mode):
            row['kind'] = 'directory'; rows.append(row)
            for child in sorted(path.iterdir()):
                visit(child)
        else:
            require(stat.S_ISREG(info.st_mode) and info.st_size <= MAX_SITE_BYTES - total,
                    'Special or oversized site file')
            with path.open('rb') as stream:
                body = stream.read(MAX_SITE_BYTES - total + 1)
            require(len(body) == info.st_size, 'Site file changed while packaging')
            total += len(body); files[name] = body
            row.update(kind='file', bytes=len(body), sha256=digest(body)); rows.append(row)
    visit(root)
    rows.sort(key=lambda row: row['path'])
    validate_members(rows)
    expected = site_hashes(site_body)
    require({name: digest(body) for name, body in files.items()} == expected,
            'Site bytes differ from qualified manifest')
    out = io.BytesIO()
    with gzip.GzipFile(fileobj=out, mode='wb', filename='', mtime=0, compresslevel=9) as compressed:
        with tarfile.open(fileobj=compressed, mode='w|', format=tarfile.PAX_FORMAT) as archive:
            for row in rows:
                member = tarfile.TarInfo('site' if row['path'] == '.' else 'site/' + row['path'])
                member.mode = row['mode']; member.mtime = 0
                member.type = tarfile.DIRTYPE if row['kind'] == 'directory' else tarfile.REGTYPE
                if row['kind'] == 'file':
                    member.size = row['bytes']
                archive.addfile(member, io.BytesIO(files[row['path']]) if row['kind'] == 'file' else None)
    body = out.getvalue()
    require(len(body) <= MAX_ARCHIVE_BYTES, 'Site archive exceeds bound')
    descriptor = {'schemaVersion': 1, 'format': 'tar+gzip', 'archive': ARCHIVE,
                  'archiveBytes': len(body), 'archiveSHA256': digest(body),
                  'siteManifestSHA256': digest(site_body), 'members': rows}
    # Exercise the exact consumer before emitting a qualified envelope.
    admitted = admit_site(body, descriptor, site_body)
    require(admitted.files == files, 'Site transport round trip changed bytes')
    return body, descriptor


def admit_site(body, descriptor, site_body):
    """Validate the entire bounded envelope before any filesystem extraction."""
    require(isinstance(descriptor, dict) and set(descriptor) == {
        'schemaVersion', 'format', 'archive', 'archiveBytes', 'archiveSHA256',
        'siteManifestSHA256', 'members'}, 'Invalid transport descriptor')
    require(type(descriptor['schemaVersion']) is int and descriptor['schemaVersion'] == 1
            and descriptor['format'] == 'tar+gzip' and descriptor['archive'] == ARCHIVE,
            'Unknown site transport format')
    require(type(descriptor['archiveBytes']) is int and 0 < len(body) <= MAX_ARCHIVE_BYTES
            and descriptor['archiveBytes'] == len(body) and descriptor['archiveSHA256'] == digest(body)
            and descriptor['siteManifestSHA256'] == digest(site_body), 'Transport digest, size or manifest differs')
    expected = validate_members(descriptor['members'])
    hashes = site_hashes(site_body)
    require({n: r['sha256'] for n, r in expected.items() if r['kind'] == 'file'} == hashes,
            'Transport and qualified site inventories differ')
    files, modes, names, seen, end = {}, {}, [], set(), 0
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(body), mode='rb') as compressed:
            raw = compressed.read(MAX_TAR_BYTES + 1)
        require(len(raw) <= MAX_TAR_BYTES, 'Expanded site archive exceeds bound')
        with tarfile.open(fileobj=io.BytesIO(raw), mode='r|') as archive:
            for member in archive:
                require(len(names) < MAX_MEMBERS, 'Too many site archive entries')
                name = '.' if member.name == 'site' else member.name.removeprefix('site/')
                require(member.name == ('site' if name == '.' else 'site/' + safe_path(name))
                        and name in expected and name not in seen, 'Unexpected or duplicate site archive path')
                row = expected[name]
                require(member.type == (tarfile.DIRTYPE if row['kind'] == 'directory' else tarfile.REGTYPE)
                        and member.sparse is None and member.mode == row['mode']
                        and member.size == row.get('bytes', 0), 'Site member type, mode or size differs')
                require(set(member.pax_headers) <= {'path'} and member.uid == member.gid == member.mtime == 0
                        and member.uname == member.gname == '', 'Unexpected site archive metadata')
                names.append(name); seen.add(name); modes[name] = member.mode
                end = max(end, member.offset_data + (member.size + 511) // 512 * 512)
                if row['kind'] == 'file':
                    stream = archive.extractfile(member)
                    data = stream.read(row['bytes'] + 1)
                    require(len(data) == row['bytes'] and digest(data) == row['sha256'], 'Site member bytes differ')
                    files[name] = data
        require(names == list(expected) and len(raw) - end >= 1024 and not any(raw[end:]),
                'Missing site members or trailing archive payload')
    except (OSError, EOFError, tarfile.TarError) as error:
        raise ValueError('Invalid compressed site archive') from error
    return Site(files, modes)


def write_site(site, target):
    """Materialize already admitted data in one new owned destination, preserving modes."""
    target = Path(target)
    require(not target.exists() and not target.is_symlink(), 'Site destination must be absent')
    directories = [n for n in site.modes if n not in site.files]
    for name in directories:
        (target / name).mkdir(mode=0o700, parents=True, exist_ok=True)
    for name, body in site.files.items():
        path = target / name
        with path.open('xb') as stream:
            stream.write(body)
        path.chmod(site.modes[name])
    for name in sorted(directories, key=lambda name: len(PurePosixPath(name).parts), reverse=True):
        (target / name).chmod(site.modes[name])
