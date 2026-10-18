#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Admit an exact successful main site's artifact before a separate Pages job.

The read-only admission job runs reviewed main tooling. The privileged deploy job
never checks out source or executes artifact contents. Importing this module is
pure; tests use offline metadata and ZIP bodies, never the API or a deployment.
"""
import argparse
import datetime
import io
import json
import os
from pathlib import Path
import re
import stat
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from documentation_transport import (ARCHIVE, DESCRIPTOR, admit_site, write_site,
                                     require, digest, strict_json, safe_path)

REPOSITORY = 'ThorFuchs/Swift-Liquid'
REPOSITORY_ID = 1419107517
LANES = ['native', 'safety', 'docs', 'reference', 'platforms', 'installation']
CHECKS = {'Swift 6.4 / ' + lane for lane in LANES} | {'Qualify clean source archive', 'Repository correctness'}
MAX_ZIP = 64 * 1024 * 1024
MAX_EXPANDED = 256 * 1024 * 1024


def validate_run(repository, run, workflow, jobs, commit, context, main):
    require(re.fullmatch('[0-9a-f]{40}', commit), 'Full source commit required')
    require(context.get('GITHUB_REPOSITORY') == REPOSITORY
            and context.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and context.get('GITHUB_REF') == 'refs/heads/main'
            and context.get('GITHUB_SHA') == commit, 'Only exact main dispatch is admitted')
    require(repository.get('id') == REPOSITORY_ID and repository.get('full_name') == REPOSITORY,
            'Wrong repository identity')
    require(type(run.get('id')) is int and run['id'] > 0
            and type(run.get('run_attempt')) is int and run['run_attempt'] > 0
            and type(workflow.get('id')) is int and workflow['id'] > 0, 'Explicit run/attempt/workflow identities required')
    require(run.get('repository', {}).get('id') == REPOSITORY_ID
            and run.get('head_repository', {}).get('id') == REPOSITORY_ID,
            'Foreign run source is forbidden')
    require(run.get('event') == 'push' and run.get('head_branch') == 'main'
            and run.get('head_sha') == commit and run.get('path') == '.github/workflows/ci.yml'
            and run.get('workflow_id') == workflow.get('id')
            and workflow.get('path') == '.github/workflows/ci.yml', 'Wrong correctness run source or workflow')
    require(run.get('status') == 'completed' and run.get('conclusion') == 'success',
            'Correctness run did not succeed')
    require(main.get('commit', {}).get('sha') == commit, 'Main moved; dispatch must be reconsidered')
    names = [job.get('name') for job in jobs]
    require(len(names) == len(CHECKS) and set(names) == CHECKS, 'Missing, duplicate or unexpected required job')
    for job in jobs:
        require(job.get('run_id') == run['id'] and job.get('head_sha') == commit
                and job.get('status') == 'completed' and job.get('conclusion') == 'success',
                'Every exact-source correctness job must succeed')


def validate_run_stable(before, after):
    keys = ['id', 'run_attempt', 'status', 'conclusion', 'head_sha', 'event', 'head_branch', 'workflow_id', 'path']
    require(all(before.get(key) == after.get(key) for key in keys),
            'Correctness run/attempt changed during admission')


def utc_timestamp(value):
    require(isinstance(value, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z', value),
            'Literal UTC artifact/job timestamp required')
    return datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))


def validate_artifact(metadata, run, docs_job):
    origin = metadata.get('workflow_run', {})
    require(metadata.get('name') == 'liquid-docs' and metadata.get('expired') is False
            and type(metadata.get('id')) is int and metadata['id'] > 0,
            'Wrong, absent or expired documentation artifact')
    require(origin.get('id') == run['id'] and origin.get('repository_id') == REPOSITORY_ID
            and origin.get('head_repository_id') == REPOSITORY_ID
            and origin.get('head_branch') == 'main' and origin.get('head_sha') == run['head_sha'],
            'Artifact origin does not match the admitted main run')
    require(isinstance(metadata.get('digest'), str)
            and re.fullmatch('sha256:[0-9a-f]{64}', metadata['digest']), 'Artifact digest required')
    require(type(metadata.get('size_in_bytes')) is int and 0 < metadata['size_in_bytes'] <= MAX_ZIP,
            'Artifact download size outside admitted bound')
    require(docs_job.get('name') == 'Swift 6.4 / docs' and docs_job.get('run_id') == run['id']
            and docs_job.get('head_sha') == run['head_sha'] and docs_job.get('conclusion') == 'success',
            'Latest-attempt documentation job required')
    started, completed = (utc_timestamp(docs_job.get(key)) for key in ['started_at', 'completed_at'])
    created, updated = (utc_timestamp(metadata.get(key)) for key in ['created_at', 'updated_at'])
    require(started <= created <= updated <= completed,
            'Artifact was not created/finalized inside admitted latest-attempt documentation job')


def admit_zip(body, metadata, run, tree, docs_job):
    validate_artifact(metadata, run, docs_job)
    require(len(body) == metadata['size_in_bytes'] and 'sha256:' + digest(body) == metadata['digest'],
            'Downloaded artifact digest/size mismatch')
    files = {}
    with zipfile.ZipFile(io.BytesIO(body)) as archive:
        infos = archive.infolist()
        require(len(infos) <= 20000 and sum(item.file_size for item in infos) <= MAX_EXPANDED,
                'Expanded artifact outside admitted bound')
        names = set()
        for item in infos:
            name = safe_path(item.filename[:-1] if item.is_dir() else item.filename)
            require(name.casefold() not in names, 'Duplicate or case-ambiguous artifact path')
            names.add(name.casefold())
            mode = item.external_attr >> 16
            require(not stat.S_ISLNK(mode) and (stat.S_IFMT(mode) in [0, stat.S_IFREG, stat.S_IFDIR]),
                    'Links or special files in artifact')
            if not item.is_dir():
                files[name] = archive.read(item)
    require({'receipt.json', 'site.json', ARCHIVE, DESCRIPTOR} <= set(files), 'Documentation transport metadata missing')
    require(not any(name == 'site' or name.startswith('site/') or name.startswith('Liquid.doccarchive/')
                    for name in files), 'Raw DocC/site trees must not enter the ZIP transport')
    receipt, site = strict_json(files['receipt.json']), strict_json(files['site.json'])
    revision = {'commit': run['head_sha'], 'tree': tree, 'clean': True}
    require(receipt.get('lane') == 'docs' and receipt.get('status') == 'passed'
            and receipt.get('sourceQualified') is True and receipt.get('sourceUnchanged') is True
            and receipt.get('sourceRevision') == revision and receipt.get('endingSourceRevision') == revision,
            'Documentation receipt is not bound to exact clean main')
    sources = receipt.get('sources', [])
    require(sources and len({row['path'] for row in sources}) == len(sources), 'Invalid source inventory')
    for row in sources:
        safe_path(row['path'])
        require(re.fullmatch('[0-9a-f]{64}', row['sha256']), 'Invalid source digest')
    info = site.get('buildInformation', {})
    require(site.get('status') == 'passed' and site.get('basePath') == '/Swift-Liquid'
            and info.get('sourceCommit') == run['head_sha'] and info.get('sourceState') == 'clean'
            and info.get('documentationTracks') == 'main'
            and info.get('runURL') == 'https://github.com/' + REPOSITORY + '/actions/runs/' + str(run['id'])
            and info.get('sourceInventorySHA256') == digest(json.dumps(sources, sort_keys=True).encode()),
            'Site build provenance differs from qualified run/source inventory')
    actual = admit_site(files[ARCHIVE], strict_json(files[DESCRIPTOR]), files['site.json'])
    require(sum(len(data) for name, data in files.items() if name != ARCHIVE)
            + sum(len(data) for data in actual.files.values()) <= MAX_EXPANDED, 'Combined expanded artifact exceeds bound')
    require({'index.html', 'build-info.json', '.nojekyll'} <= set(actual.files), 'Required site bodies missing')
    require(strict_json(actual.files['build-info.json']) == info, 'Embedded site provenance mismatch')
    return actual


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


class GitHub:
    def __init__(self, token):
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect)

    def request(self, route, limit=10 * 1024 * 1024):
        require(route == '/repos/' + REPOSITORY or route.startswith('/repos/' + REPOSITORY + '/'),
                'Unexpected API route')
        request = urllib.request.Request('https://api.github.com' + route, headers={
            'Authorization': 'Bearer ' + self.token, 'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28'})
        with self.opener.open(request, timeout=60) as response:
            body = response.read(limit + 1)
        require(len(body) <= limit, 'API response exceeds bound')
        return body

    def json(self, route):
        return strict_json(self.request(route))

    def download(self, artifact_id):
        try:
            self.request('/repos/' + REPOSITORY + '/actions/artifacts/' + str(artifact_id) + '/zip')
        except urllib.error.HTTPError as error:
            require(error.code == 302, 'Artifact download did not provide an admitted redirect')
            location = error.headers.get('Location', '')
            error.close()
            parsed = urllib.parse.urlparse(location)
            require(parsed.scheme == 'https' and parsed.hostname and not parsed.username and not parsed.password
                    and parsed.hostname.endswith(('.blob.core.windows.net', '.actions.githubusercontent.com', '.githubusercontent.com')),
                    'Untrusted artifact download host')
            # The signed storage request receives no GitHub Authorization header.
            with self.opener.open(urllib.request.Request(location), timeout=60) as response:
                body = response.read(MAX_ZIP + 1)
            require(len(body) <= MAX_ZIP, 'Artifact download exceeds bound')
            return body
        raise ValueError('Expected one signed artifact storage redirect')

    def pages(self, route, key):
        rows = []
        for page in range(1, 11):
            data = self.json(route + '?per_page=100&page=' + str(page))
            rows += data[key]
            if len(rows) == data['total_count']:
                return rows
            require(len(rows) < data['total_count'] and data[key], 'Inconsistent API pagination')
        raise ValueError('API pagination exceeds admitted bound')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--approval-record', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(re.fullmatch('[1-9][0-9]*', args.run_id), 'Numeric correctness run ID required')
    require(re.fullmatch('[0-9a-f]{40}', args.commit), 'Full source commit required')
    require(args.approval_record.strip(), 'Explicit deployment approval record required')
    args.output.mkdir(parents=True, exist_ok=False)
    record = {'status': 'failed', 'sourceCommit': args.commit, 'correctnessRunID': int(args.run_id),
              'approvalRecord': args.approval_record,
              'authorityLimit': 'Metadata admission does not grant or independently verify human approval'}
    try:
        api = GitHub(os.environ['GH_TOKEN'])
        base = '/repos/' + REPOSITORY
        repository = api.json(base)
        run = api.json(base + '/actions/runs/' + args.run_id)
        require(run.get('id') == int(args.run_id), 'Wrong run ID')
        workflow = api.json(base + '/actions/workflows/ci.yml')
        attempt = run.get('run_attempt')
        require(type(attempt) is int and attempt > 0, 'Run attempt identity required')
        jobs = api.pages(base + '/actions/runs/' + args.run_id + '/attempts/' + str(attempt) + '/jobs', 'jobs')
        main = api.json(base + '/branches/main')
        validate_run(repository, run, workflow, jobs, args.commit, os.environ, main)
        docs_job = next(job for job in jobs if job['name'] == 'Swift 6.4 / docs')
        artifacts = api.pages(base + '/actions/runs/' + args.run_id + '/artifacts', 'artifacts')
        selected = [row for row in artifacts if row.get('name') == 'liquid-docs']
        require(len(selected) == 1, 'Exactly one qualified docs artifact required')
        metadata = selected[0]
        validate_artifact(metadata, run, docs_job)
        tree = main['commit']['commit']['tree']['sha']
        site = admit_zip(api.download(metadata['id']), metadata, run, tree, docs_job)
        ending_run = api.json(base + '/actions/runs/' + args.run_id)
        validate_run_stable(run, ending_run)
        require(api.json(base + '/branches/main')['commit']['sha'] == args.commit, 'Main moved during admission')
        target = args.output / 'site'
        write_site(site, target)
        record.update(status='passed', repository=repository['full_name'], run=run, endingRun=ending_run,
                      requiredJobs=jobs, artifact=metadata, sourceTree=tree,
                      siteFiles=[{'path': name, 'sha256': digest(body), 'mode': site.modes[name]}
                                 for name, body in sorted(site.files.items())],
                      limitation='Fresh sequential main observations are not a branch lock; no source or artifact code executed')
    except (ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile) as error:
        record['error'] = str(error)
    (args.output / 'admission.json').write_text(json.dumps(record, indent=2) + '\n')
    return 0 if record['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
