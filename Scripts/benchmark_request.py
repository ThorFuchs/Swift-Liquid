#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Bind a separately commissioned manual benchmark request; never launch timing."""
import json
import os
from pathlib import Path
import re
import subprocess

BASELINE = '9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e'


def admit(context, actual_commit, clean):
    commit = context.get('SOURCE_COMMIT', '')
    if (context.get('GITHUB_REPOSITORY') != 'ThorFuchs/Swift-Liquid'
            or context.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
            or not re.fullmatch('[0-9a-f]{40}', commit)
            or context.get('CONFIRMATION') != 'Separate timing commission approved'
            or not context.get('COMMISSION_RECORD', '').strip()
            or commit != context.get('GITHUB_SHA') or actual_commit != commit or not clean):
        raise ValueError('Explicit timing commission and exact clean dispatch source required')
    return {'sourceCommit': commit, 'baselineCommit': BASELINE,
            'commissionRecord': context['COMMISSION_RECORD'],
            'status': 'MEASURED_UNACCEPTED_IF_COMPLETED',
            'authorityLimit': 'This request neither independently verifies nor grants human timing authority; separate host/protocol admission remains required'}


def main():
    env = os.environ.copy()
    env.update(GIT_OPTIONAL_LOCKS='0', GIT_NO_LAZY_FETCH='1', GIT_NO_REPLACE_OBJECTS='1')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], env=env, text=True).strip()
    clean = not subprocess.check_output(['git', 'status', '--porcelain'], env=env, text=True).strip()
    record = admit(os.environ, commit, clean)
    output = Path('Artifacts/benchmark-request.json')
    output.parent.mkdir(exist_ok=True)
    # A request belongs to one fresh hosted invocation; never overwrite one.
    with output.open('x') as stream:
        stream.write(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
