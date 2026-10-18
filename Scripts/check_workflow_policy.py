#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Semantic regression checks for the hosted contribution/publishing boundary."""
import copy
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import zipfile
from ci import ROOT
from workflow_policy import load_yaml, validate, audit
from benchmark_request import admit as admit_benchmark
from documentation_admission import (REPOSITORY, REPOSITORY_ID, CHECKS, GitHub,
                                     validate_run, validate_run_stable, validate_artifact, admit_zip, digest, strict_json)
import documentation_transport as transport
from documentation_transport import ARCHIVE, DESCRIPTOR, pack_site, admit_site, write_site


class WorkflowPolicyTests(unittest.TestCase):
    def setUp(self):
        self.document = load_yaml((ROOT / '.github/workflows/ci.yml').read_text())

    def test_reviewed_workflow_passes(self):
        self.assertEqual(validate(self.document)['runnerLabels'], ['xcode-27', 'ubuntu-latest'])
        self.assertEqual(set(audit(ROOT / '.github/workflows/ci.yml')),
                         {'ci.yml', 'benchmarks.yml', 'documentation.yml'})

    def test_shared_or_dynamic_runner_selection_is_rejected(self):
        for runner in [['self-hosted', 'macOS'], 'macos-latest', '${{ inputs.runner }}']:
            changed = copy.deepcopy(self.document); changed['jobs']['qualify']['runs-on'] = runner
            with self.subTest(runner=runner), self.assertRaises(RuntimeError): validate(changed)
        changed = copy.deepcopy(self.document); changed['jobs']['archive']['steps'].pop(0)
        with self.assertRaises(RuntimeError): validate(changed)

    def test_privileged_triggers_permissions_and_credentials_are_rejected(self):
        for change in ['trigger', 'default-write', 'build-write', 'secret', 'checkout-ref', 'persist', 'cache']:
            changed = copy.deepcopy(self.document); job = changed['jobs']['qualify']
            if change == 'trigger': changed['on']['pull_request_target'] = None
            elif change == 'default-write': changed['permissions'] = {'contents': 'write'}
            elif change == 'build-write': job['permissions'] = {'contents': 'read', 'id-token': 'write'}
            elif change == 'secret': job['env']['KEY'] = '${{ secrets.KEY }}'
            elif change == 'checkout-ref': job['steps'][1]['with']['ref'] = '${{ github.event.pull_request.head.sha }}'
            elif change == 'persist': job['steps'][1]['with']['persist-credentials'] = True
            else: job['steps'].append({'uses': 'actions/cache@' + 'a' * 40})
            with self.subTest(change=change), self.assertRaises(RuntimeError): validate(changed)

    def test_runner_context_must_be_exported_from_a_step(self):
        changed = copy.deepcopy(self.document)
        changed['jobs']['qualify']['env']['LIQUID_RUNNER_ENVIRONMENT'] = '${{ runner.environment }}'
        with self.assertRaises(RuntimeError): validate(changed)
        changed = copy.deepcopy(self.document)
        changed['jobs']['archive']['steps'][0]['run'] = 'test "$RUNNER_ENVIRONMENT" = "github-hosted"'
        with self.assertRaises(RuntimeError): validate(changed)

    def test_publishing_requires_manual_main_admission_and_no_privileged_checkout(self):
        document = load_yaml((ROOT / '.github/workflows/documentation.yml').read_text())
        for change in ['condition', 'needs', 'checkout', 'script', 'permissions', 'environment', 'trigger', 'artifact-override']:
            changed = copy.deepcopy(document); job = changed['jobs']['deploy']
            if change == 'condition': job['if'] = 'always()'
            elif change == 'needs': job['needs'] = []
            elif change == 'checkout': job['steps'].append(copy.deepcopy(changed['jobs']['admit']['steps'][1]))
            elif change == 'script': job['steps'].append({'run': 'python3 untrusted.py'})
            elif change == 'permissions': job['permissions']['contents'] = 'write'
            elif change == 'environment': job['environment']['name'] = 'production'
            elif change == 'trigger': changed['on']['workflow_run'] = {'workflows': ['Swift-Liquid CI']}
            else: job['steps'][-1]['with'] = {'artifact_name': 'unqualified-site'}
            with self.subTest(change=change), self.assertRaises(RuntimeError): validate(changed, 'documentation')

    def test_routine_timing_and_incomplete_aggregate_are_rejected(self):
        for change in ['timing-lane', 'timing-step', 'skip-archive', 'aggregate-condition',
                       'aggregate-needs', 'aggregate-body', 'aggregate-input', 'matrix-tolerance', 'step-tolerance']:
            changed = copy.deepcopy(self.document)
            q, a, c = (changed['jobs'][name] for name in ['qualify', 'archive', 'correctness'])
            if change == 'timing-lane': q['strategy']['matrix']['lane'].append('performance')
            elif change == 'timing-step': q['steps'].append({'run': 'python3 -B Scripts/ci.py --lane matched-performance'})
            elif change == 'skip-archive': a['if'] = 'false'
            elif change == 'aggregate-condition': c['if'] = 'success()'
            elif change == 'aggregate-needs': c['needs'] = ['qualify']
            elif change == 'aggregate-body': c['steps'][1]['run'] = 'echo success'
            elif change == 'aggregate-input': c['steps'][1]['env']['NEEDS_JSON'] = '{}'
            elif change == 'matrix-tolerance': q['continue-on-error'] = True
            else: a['steps'][-2]['continue-on-error'] = True
            with self.subTest(change=change), self.assertRaises(RuntimeError): validate(changed)

    def test_actual_aggregate_program_fails_closed_for_every_non_success(self):
        script = self.document['jobs']['correctness']['steps'][1]['run']
        for member in ['qualify', 'archive']:
            for conclusion in ['success', 'failure', 'skipped', 'cancelled', 'neutral', None, 'unknown']:
                needs = {'qualify': {'result': 'success'}, 'archive': {'result': 'success'}}
                needs[member]['result'] = conclusion
                result = subprocess.run(['/bin/bash', '-e', '-c', script],
                    env={**os.environ, 'NEEDS_JSON': json.dumps(needs)}, capture_output=True)
                with self.subTest(member=member, conclusion=conclusion):
                    self.assertEqual(result.returncode == 0, conclusion == 'success')
        for needs in [{}, {'qualify': {'result': 'success'}},
                      {'qualify': {'result': 'success'}, 'archive': {}},
                      {'qualify': {'result': 'success'}, 'archive': {'result': 'success'}, 'extra': {'result': 'success'}}]:
            result = subprocess.run(['/bin/bash', '-e', '-c', script],
                env={**os.environ, 'NEEDS_JSON': json.dumps(needs)}, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_controlled_benchmark_workflow_cannot_become_routine_or_unbound(self):
        original = load_yaml((ROOT / '.github/workflows/benchmarks.yml').read_text())
        validate(original, 'benchmarks')
        for change in ['push', 'schedule', 'checkout-ref', 'source-bind', 'measure-condition', 'parallel', 'baseline']:
            d = copy.deepcopy(original); job = d['jobs']['benchmarks']
            if change == 'push': d['on']['push'] = {'branches': ['main']}
            elif change == 'schedule': d['on']['schedule'] = [{'cron': '* * * * *'}]
            elif change == 'checkout-ref': job['steps'][1]['with']['ref'] = '${{ inputs.source_commit }}'
            elif change == 'source-bind': job['steps'][2]['run'] = 'echo admitted'
            elif change == 'measure-condition': job['steps'][5]['if'] = 'always()'
            elif change == 'parallel': d['concurrency']['cancel-in-progress'] = True
            else: job['steps'][3]['run'] = 'git fetch origin main'
            with self.subTest(change=change), self.assertRaises(RuntimeError): validate(d, 'benchmarks')

    def test_unpinned_actions_and_reduced_gates_are_rejected(self):
        changed = copy.deepcopy(self.document); changed['jobs']['archive']['steps'][1]['uses'] = 'actions/checkout@v6'
        with self.assertRaises(RuntimeError): validate(changed)
        changed = copy.deepcopy(self.document); changed['jobs']['qualify']['strategy']['matrix']['lane'].remove('safety')
        with self.assertRaises(RuntimeError): validate(changed)

    def test_raw_docc_and_site_trees_cannot_reenter_zip_upload(self):
        for exclusion in ['!Artifacts/docs/site/**\n', '!Artifacts/docs/Liquid.doccarchive/**\n']:
            changed = copy.deepcopy(self.document)
            upload = changed['jobs']['qualify']['steps'][-1]['with']
            upload['path'] = upload['path'].replace(exclusion, '')
            with self.subTest(exclusion=exclusion), self.assertRaises(RuntimeError): validate(changed)

    def test_ambiguous_yaml_and_object_construction_are_rejected(self):
        for source in ['jobs: {}\njobs: {}\n', 'a: &shared {}\nb: *shared\n', '---\na: 1\n---\nb: 2\n', 'x: !ruby/object:Object {}\n']:
            with self.subTest(source=source), self.assertRaises(RuntimeError): load_yaml(source)

    def test_inserted_allowed_action_cache_and_execution_substitutions_fail(self):
        for filename, kind in [('ci.yml', 'ci'), ('benchmarks.yml', 'benchmarks'), ('documentation.yml', 'documentation')]:
            document = load_yaml((ROOT / '.github/workflows' / filename).read_text())
            for job_name in document['jobs']:
                d = copy.deepcopy(document)
                d['jobs'][job_name]['steps'].insert(2, {'uses': 'ruby/setup-ruby@651ff0d62c5c79bed6d53ec518387aae20e72c1a',
                    'with': {'ruby-version': '4.0.1', 'bundler-cache': True}})
                with self.subTest(kind=kind, job=job_name, mutation='insert-cache'), self.assertRaises(RuntimeError):
                    validate(d, kind)
                d = copy.deepcopy(document); d['jobs'][job_name]['env'] = {'BASH_ENV': 'untrusted.sh'}
                with self.subTest(kind=kind, job=job_name, mutation='environment'), self.assertRaises(RuntimeError):
                    validate(d, kind)
            d = copy.deepcopy(document); d['defaults'] = {'run': {'working-directory': 'other'}}
            with self.subTest(kind=kind, mutation='defaults'), self.assertRaises(RuntimeError): validate(d, kind)


class BenchmarkRequestTests(unittest.TestCase):
    def test_full_source_and_separate_commission_are_required_without_launching_timing(self):
        commit = 'a' * 40
        context = {'GITHUB_REPOSITORY': REPOSITORY, 'GITHUB_EVENT_NAME': 'workflow_dispatch',
            'GITHUB_SHA': commit, 'SOURCE_COMMIT': commit, 'COMMISSION_RECORD': 'separate-test-commission',
            'CONFIRMATION': 'Separate timing commission approved'}
        self.assertEqual(admit_benchmark(context, commit, True)['sourceCommit'], commit)
        for key, value in [('SOURCE_COMMIT', 'main'), ('SOURCE_COMMIT', 'b' * 40),
                           ('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_REPOSITORY', 'fork/Liquid'),
                           ('COMMISSION_RECORD', ''), ('CONFIRMATION', 'Not commissioned')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                admit_benchmark({**context, key: value}, commit, True)
        for actual, clean in [(commit, False), ('b' * 40, True)]:
            with self.assertRaises(ValueError): admit_benchmark(context, actual, clean)


class DocumentationAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.commit, self.tree = 'a' * 40, 'b' * 40
        self.repository = {'id': REPOSITORY_ID, 'full_name': REPOSITORY}
        self.run = {'id': 123, 'run_attempt': 2, 'repository': {'id': REPOSITORY_ID},
            'head_repository': {'id': REPOSITORY_ID}, 'event': 'push', 'head_branch': 'main',
            'head_sha': self.commit, 'path': '.github/workflows/ci.yml', 'workflow_id': 12,
            'status': 'completed', 'conclusion': 'success'}
        self.workflow = {'id': 12, 'path': '.github/workflows/ci.yml'}
        self.jobs = [{'name': name, 'run_id': 123, 'head_sha': self.commit, 'status': 'completed',
                      'conclusion': 'success', 'started_at': '2026-10-18T01:00:00Z',
                      'completed_at': '2026-10-18T01:10:00Z'} for name in sorted(CHECKS)]
        self.docs_job = next(job for job in self.jobs if job['name'] == 'Swift 6.4 / docs')
        self.context = {'GITHUB_REPOSITORY': REPOSITORY, 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                        'GITHUB_REF': 'refs/heads/main', 'GITHUB_SHA': self.commit}
        self.main = {'commit': {'sha': self.commit}}
        sources = [{'path': 'Package.swift', 'sha256': 'c' * 64}]
        info = {'sourceCommit': self.commit, 'sourceState': 'clean', 'documentationTracks': 'main',
                'sourceInventorySHA256': digest(json.dumps(sources, sort_keys=True).encode()),
                'runURL': 'https://github.com/' + REPOSITORY + '/actions/runs/123'}
        self.site_files = {'index.html': b'<html>qualified main</html>', '.nojekyll': b'',
                           'build-info.json': json.dumps(info).encode(),
                           'data/documentation/liquid/liquiddependencyedge/!=(_:_:).json': b'{"qualified":true}',
                           'data/über/Δ(_:).json': b'{"unicode":true}'}
        revision = {'commit': self.commit, 'tree': self.tree, 'clean': True}
        self.receipt = {'lane': 'docs', 'status': 'passed', 'sourceQualified': True, 'sourceUnchanged': True,
                        'sourceRevision': revision, 'endingSourceRevision': revision, 'sources': sources}
        self.site = {'status': 'passed', 'basePath': '/Swift-Liquid', 'buildInformation': info,
                     'files': [{'path': name, 'sha256': digest(body)} for name, body in self.site_files.items()]}
        self.metadata = {'id': 9, 'name': 'liquid-docs', 'expired': False,
            'created_at': '2026-10-18T01:05:00Z', 'updated_at': '2026-10-18T01:06:00Z', 'workflow_run': {
            'id': 123, 'repository_id': REPOSITORY_ID, 'head_repository_id': REPOSITORY_ID,
            'head_branch': 'main', 'head_sha': self.commit}}

    def archive(self, extras=()):
        site_body = json.dumps(self.site).encode()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'site'; root.mkdir()
            for name, body in self.site_files.items():
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(body)
            # Malicious body tests deliberately keep the separately recorded site
            # manifest unchanged. Build the archive independently, then bind its
            # descriptor to that claimed manifest so admission must reject it.
            actual_manifest = json.dumps({**self.site, 'files': [
                {'path': name, 'sha256': digest(body)} for name, body in self.site_files.items()]}).encode()
            envelope, descriptor = pack_site(root, actual_manifest)
            descriptor['siteManifestSHA256'] = digest(site_body)
        out = io.BytesIO()
        with zipfile.ZipFile(out, 'w') as z:
            z.writestr('receipt.json', json.dumps(self.receipt))
            z.writestr('site.json', site_body)
            z.writestr(ARCHIVE, envelope)
            z.writestr(DESCRIPTOR, json.dumps(descriptor))
            for name, body, mode in extras:
                entry = zipfile.ZipInfo(name); entry.external_attr = mode << 16; z.writestr(entry, body)
        body = out.getvalue()
        return body, {**self.metadata, 'size_in_bytes': len(body), 'digest': 'sha256:' + digest(body)}

    def test_success_requires_actual_main_run_jobs_and_all_site_bytes(self):
        validate_run(self.repository, self.run, self.workflow, self.jobs, self.commit, self.context, self.main)
        body, metadata = self.archive()
        self.assertEqual(admit_zip(body, metadata, self.run, self.tree, self.docs_job).files, self.site_files)
        with zipfile.ZipFile(io.BytesIO(body)) as archive:
            self.assertTrue(all(':' not in name for name in archive.namelist()))
            self.assertFalse(any(name.startswith('site/') for name in archive.namelist()))

    def test_wrong_event_source_repository_run_workflow_and_moved_main_fail(self):
        for key, value in [('event', 'pull_request'), ('head_branch', 'feature'), ('head_sha', 'd' * 40),
                           ('path', '.github/workflows/other.yml'), ('workflow_id', 13),
                           ('status', 'in_progress'), ('conclusion', 'neutral'),
                           ('head_repository', {'id': 1})]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_run(self.repository, {**self.run, key: value}, self.workflow, self.jobs,
                             self.commit, self.context, self.main)
        for context, main in [({**self.context, 'GITHUB_REF': 'refs/heads/feature'}, self.main),
                              (self.context, {'commit': {'sha': 'd' * 40}})]:
            with self.assertRaises(ValueError):
                validate_run(self.repository, self.run, self.workflow, self.jobs, self.commit, context, main)

    def test_missing_duplicate_wrong_source_or_unsuccessful_required_job_fails(self):
        for conclusion in ['failure', 'skipped', 'cancelled', 'neutral', None]:
            jobs = copy.deepcopy(self.jobs); jobs[0]['conclusion'] = conclusion
            with self.subTest(conclusion=conclusion), self.assertRaises(ValueError):
                validate_run(self.repository, self.run, self.workflow, jobs, self.commit, self.context, self.main)
        for jobs in [self.jobs[:-1], self.jobs + [self.jobs[0]],
                     [{**self.jobs[0], 'head_sha': 'd' * 40}] + self.jobs[1:]]:
            with self.assertRaises(ValueError):
                validate_run(self.repository, self.run, self.workflow, jobs, self.commit, self.context, self.main)

    def test_expired_wrong_origin_digest_and_source_receipts_fail(self):
        body, metadata = self.archive()
        for changes in [{'expired': True}, {'digest': 'sha256:' + '0' * 64}, {'size_in_bytes': len(body) + 1},
                        {'workflow_run': {**metadata['workflow_run'], 'id': 456}},
                        {'workflow_run': {**metadata['workflow_run'], 'head_sha': 'd' * 40}}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                admit_zip(body, {**metadata, **changes}, self.run, self.tree, self.docs_job)
        for field in ['sourceQualified', 'sourceUnchanged']:
            self.receipt[field] = False; body, metadata = self.archive()
            with self.assertRaises(ValueError): admit_zip(body, metadata, self.run, self.tree, self.docs_job)
            self.receipt[field] = True
        body, metadata = self.archive()
        with self.assertRaises(ValueError): admit_zip(body, metadata, self.run, 'd' * 40, self.docs_job)

    def test_altered_missing_extra_and_escaping_site_bodies_fail(self):
        for name, value in [('index.html', b'altered'), ('extra.html', b'extra')]:
            original = dict(self.site_files); self.site_files[name] = value
            body, metadata = self.archive()
            with self.assertRaises(ValueError): admit_zip(body, metadata, self.run, self.tree, self.docs_job)
            self.site_files = original
        for name, body, mode in [('site/../escape', b'x', stat.S_IFREG | 0o644),
                                 ('site/link', b'../../escape', stat.S_IFLNK | 0o777),
                                 ('site/INDEX.html', b'ambiguous', stat.S_IFREG | 0o644)]:
            body, metadata = self.archive([(name, body, mode)])
            with self.assertRaises(ValueError): admit_zip(body, metadata, self.run, self.tree, self.docs_job)
        with self.assertRaises(ValueError): strict_json(b'{"passed":true,"passed":false}')

    def test_old_attempt_same_run_and_head_or_unknown_timestamp_cannot_supply_site(self):
        body, metadata = self.archive()
        for change in [{'created_at': '2026-10-17T01:05:00Z', 'updated_at': '2026-10-17T01:06:00Z'},
                       {'created_at': None}, {'updated_at': '2026-10-18T01:11:00Z'},
                       {'created_at': '2026-10-18T01:07:00Z'}, {'created_at': '2026-10-18T01:05:00+01:00'}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                admit_zip(body, {**metadata, **change}, self.run, self.tree, self.docs_job)

    def test_rerun_race_or_absent_workflow_identity_cannot_supply_admission(self):
        validate_run_stable(self.run, dict(self.run))
        for key, value in [('run_attempt', 3), ('status', 'in_progress'), ('conclusion', None)]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_run_stable(self.run, {**self.run, key: value})
        invalid_run = {**self.run, 'workflow_id': None}
        with self.assertRaises(ValueError):
            validate_run(self.repository, invalid_run, {'path': '.github/workflows/ci.yml'}, self.jobs,
                         self.commit, self.context, self.main)

    def test_signed_storage_download_receives_no_github_authorization(self):
        calls = []
        class Opener:
            def open(self, request, timeout):
                calls.append(request)
                if len(calls) == 1:
                    raise urllib.error.HTTPError(request.full_url, 302, 'redirect',
                        {'Location': 'https://test.blob.core.windows.net/artifact?signature=private'}, None)
                return io.BytesIO(b'zip body')
        api = GitHub('offline-test-token'); api.opener = Opener()
        self.assertEqual(api.download(9), b'zip body')
        self.assertIn('Authorization', calls[0].headers)
        self.assertNotIn('Authorization', calls[1].headers)


class DocumentationTransportTests(unittest.TestCase):
    def specimen(self, root):
        root.mkdir(mode=0o750)
        files = {'index.html': b'<p>site</p>', '.nojekyll': b'',
                 'data/Δ/!=(_:_:).json': b'{"unchanged":true}'}
        for name, body in files.items():
            path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(body)
            path.chmod(0o640)
        (root / 'empty').mkdir(mode=0o700)
        manifest = json.dumps({'files': [{'path': name, 'sha256': digest(body)} for name, body in files.items()]}).encode()
        return files, manifest

    def rewrite(self, body, descriptor, edit, trailing=b''):
        out = io.BytesIO()
        with tarfile.open(fileobj=io.BytesIO(body), mode='r:gz') as source:
            entries = [(copy.copy(member), source.extractfile(member).read() if member.isfile() else None)
                       for member in source]
        entries = edit(entries)
        with tarfile.open(fileobj=out, mode='w', format=tarfile.PAX_FORMAT) as archive:
            for member, data in entries:
                archive.addfile(member, io.BytesIO(data) if data is not None else None)
        raw = out.getvalue() + trailing
        import gzip
        body = gzip.compress(raw, mtime=0)
        descriptor = {**descriptor, 'archiveBytes': len(body), 'archiveSHA256': digest(body)}
        return body, descriptor

    def test_real_declaration_names_hidden_files_empty_directories_and_modes_round_trip(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'site'; files, manifest = self.specimen(root)
            body, descriptor = pack_site(root, manifest)
            self.assertEqual((body, descriptor), pack_site(root, manifest))
            admitted = admit_site(body, descriptor, manifest)
            self.assertEqual(admitted.files, files); self.assertEqual(admitted.modes['.'], 0o750)
            self.assertEqual(admitted.modes['empty'], 0o700)
            target = Path(temporary) / 'restored'; write_site(admitted, target)
            for name, mode in admitted.modes.items():
                self.assertEqual(stat.S_IMODE((target / name).stat().st_mode), mode)
                if name in files: self.assertEqual((target / name).read_bytes(), files[name])
            with self.assertRaises(ValueError): write_site(admitted, target)
            self.assertEqual((root / 'data/Δ/!=(_:_:).json').read_bytes(), files['data/Δ/!=(_:_:).json'])

    def test_wrong_archive_manifest_descriptor_and_corrupt_compression_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'site'; _, manifest = self.specimen(root); body, descriptor = pack_site(root, manifest)
            for changes in [{'archiveSHA256': '0' * 64}, {'siteManifestSHA256': '0' * 64},
                            {'archiveBytes': len(body) + 1}, {'schemaVersion': True}, {'archive': '../site.tar.gz'},
                            {'members': descriptor['members'][:-1]}]:
                with self.subTest(changes=changes), self.assertRaises(ValueError):
                    admit_site(body, {**descriptor, **changes}, manifest)
            broken = body[:-8]
            with self.assertRaises(ValueError):
                admit_site(broken, {**descriptor, 'archiveBytes': len(broken), 'archiveSHA256': digest(broken)}, manifest)
            with patch.object(transport, 'MAX_TAR_BYTES', 1024), self.assertRaises(ValueError):
                admit_site(body, descriptor, manifest)

    def test_traversal_links_special_files_duplicate_missing_mode_and_trailing_payload_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'site'; _, manifest = self.specimen(root); body, descriptor = pack_site(root, manifest)
            def mutate(entries, variant):
                member, data = next((m, d) for m, d in entries if m.isfile())
                if variant == 'bytes':
                    member, data = next((m, d) for m, d in entries if d)
                    return [(m, (b'X' + d[1:]) if m is member else d) for m, d in entries]
                if variant == 'duplicate': return entries + [(copy.copy(member), data)]
                if variant == 'missing': return [(m, d) for m, d in entries if m.name != member.name]
                if variant == 'path': member.name = 'site/../escape'
                elif variant == 'absolute': member.name = '/site/escape'
                elif variant == 'mode': member.mode |= 0o4000
                elif variant == 'metadata': member.pax_headers = {'mtime': '1'}
                else:
                    member.type = {'symlink': tarfile.SYMTYPE, 'hardlink': tarfile.LNKTYPE, 'fifo': tarfile.FIFOTYPE}[variant]
                    member.linkname = '../../outside'; member.size = 0
                    return [(m, None if m is member else d) for m, d in entries]
                return entries
            for variant in ['bytes', 'duplicate', 'missing', 'path', 'absolute', 'mode', 'metadata', 'symlink', 'hardlink', 'fifo']:
                changed, meta = self.rewrite(body, descriptor, lambda entries: mutate(entries, variant))
                with self.subTest(variant=variant), self.assertRaises(ValueError): admit_site(changed, meta, manifest)
            changed, meta = self.rewrite(body, descriptor, lambda entries: entries, trailing=b'concealed payload')
            with self.assertRaises(ValueError): admit_site(changed, meta, manifest)

    def test_ambiguous_inventory_oversized_members_and_linked_producer_cannot_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'site'; _, manifest = self.specimen(root); body, descriptor = pack_site(root, manifest)
            for change in ['duplicate', 'case', 'size', 'parent', 'bool-mode']:
                rows = copy.deepcopy(descriptor['members']); file = next(r for r in rows if r['kind'] == 'file')
                if change == 'duplicate': rows.append(copy.copy(file))
                elif change == 'case': rows.append({**file, 'path': file['path'].upper()})
                elif change == 'size': file['bytes'] = transport.MAX_SITE_BYTES + 1
                elif change == 'parent': file['path'] = 'absent/file'
                else: file['mode'] = True
                with self.subTest(change=change), self.assertRaises(ValueError):
                    admit_site(body, {**descriptor, 'members': rows}, manifest)
            (root / 'linked').symlink_to(root / 'index.html')
            with self.assertRaises(ValueError): pack_site(root, manifest)


if __name__ == '__main__':
    unittest.main()
