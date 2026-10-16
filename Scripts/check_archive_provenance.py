#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Reject changed or ambiguous source exports without weakening checkout identity."""
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest import mock
import archive_provenance
import ci


class ArchiveProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='liquid-archive-provenance-')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / 'source'; self.root.mkdir()
        (self.root / 'input.swift').write_text('let value = "é😀"\n')
        self.archive = self.base / 'source.tar.gz'
        self.provenance = self.base / 'provenance.json'
        self.producer = {'commit': 'a' * 40, 'tree': 'b' * 40, 'clean': True}
        self.pack()
        self.value = archive_provenance.manifest(self.root, self.archive, self.producer,
                                                 self.snapshot(), ['input.swift'])
        self.save()

    def snapshot(self):
        return [{'path': 'input.swift', 'sha256': hashlib.sha256((self.root / 'input.swift').read_bytes()).hexdigest()}]

    def pack(self, commit=None):
        with tarfile.open(self.archive, 'w:gz', format=tarfile.PAX_FORMAT,
                          pax_headers={'comment': commit or self.producer['commit']}) as archive:
            archive.add(self.root / 'input.swift', 'input.swift')

    def save(self):
        self.provenance.write_text(json.dumps(self.value, indent=2) + '\n')

    def revision(self):
        return archive_provenance.revision(self.root, self.provenance, self.snapshot())

    def test_git_free_export_keeps_explicit_producer_and_byte_identity(self):
        value = self.revision()
        self.assertEqual(value['origin'], 'source-archive')
        self.assertEqual(value['commit'], self.producer['commit'])
        self.assertTrue(value['clean'])
        self.assertFalse((self.root / '.git').exists())

    def test_source_and_archive_changes_are_rejected(self):
        for kind in ['source', 'archive', 'mode']:
            with self.subTest(kind=kind):
                source = self.root / 'input.swift'; original = source.read_bytes()
                archive = self.archive.read_bytes(); mode = source.stat().st_mode
                if kind == 'source': source.write_bytes(original + b'changed')
                elif kind == 'archive': self.archive.write_bytes(archive + b'changed')
                else: source.chmod(0o755)
                with self.assertRaises(RuntimeError): self.revision()
                source.write_bytes(original); source.chmod(mode); self.archive.write_bytes(archive)

    def test_archive_commit_cannot_be_relabelled(self):
        self.value['commit'] = 'c' * 40; self.save()
        with self.assertRaises(RuntimeError): self.revision()

    def test_inventory_cannot_be_missing_duplicated_or_escape(self):
        original = copy.deepcopy(self.value)
        for inventory in [[], [original['inventory'][0]] * 2,
                          [{'path': '../input.swift', 'sha256': 'a' * 64}],
                          [{'path': 'missing.swift', 'sha256': 'a' * 64}]]:
            with self.subTest(inventory=inventory):
                self.value = dict(original, inventory=inventory); self.save()
                with self.assertRaises(RuntimeError): self.revision()

    def test_export_cannot_substitute_a_symlink(self):
        original = self.root / 'input.swift'; alternate = self.base / 'same.swift'
        alternate.write_bytes(original.read_bytes()); original.unlink(); original.symlink_to(alternate)
        with self.assertRaises(RuntimeError): self.revision()

    def test_context_cannot_override_checkout_or_live_inside_export(self):
        (self.root / '.git').write_text('not an archive')
        with self.assertRaises(RuntimeError): self.revision()
        (self.root / '.git').unlink()
        inside = self.root / 'provenance.json'; inside.write_bytes(self.provenance.read_bytes())
        with self.assertRaises(RuntimeError): archive_provenance.revision(self.root, inside, self.snapshot())

    def test_unknown_context_and_invalid_revision_fail_closed(self):
        original = copy.deepcopy(self.value)
        for changes in [{'schemaVersion': 2}, {'origin': 'git'}, {'tree': 'unknown'}, {'extra': True}]:
            with self.subTest(changes=changes):
                self.value = dict(original, **changes); self.save()
                with self.assertRaises(RuntimeError): self.revision()

    def test_context_bytes_are_part_of_start_end_identity(self):
        before = self.revision(); self.provenance.write_text(json.dumps(self.value))
        self.assertNotEqual(before['provenanceSHA256'], self.revision()['provenanceSHA256'])

    def test_default_checkout_identity_never_uses_github_sha_fallback(self):
        with mock.patch.object(ci, 'ROOT', self.root), mock.patch.dict(os.environ, {'GITHUB_SHA': 'a' * 40}):
            with self.assertRaises(subprocess.CalledProcessError): ci.source_revision()

    def test_archive_option_is_restricted_to_native(self):
        result = subprocess.run([sys.executable, '-B', str(Path(ci.__file__)), '--lane', 'safety',
                                 '--archive-provenance', str(self.provenance)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('only for native', result.stderr)


if __name__ == '__main__':
    unittest.main()
