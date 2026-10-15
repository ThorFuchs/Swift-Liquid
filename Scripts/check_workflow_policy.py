#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Semantic regression checks for the hosted contribution/publishing boundary."""
import copy
import unittest
from ci import ROOT
from workflow_policy import load_yaml, validate


class WorkflowPolicyTests(unittest.TestCase):
    def setUp(self):
        self.document = load_yaml((ROOT / '.github/workflows/ci.yml').read_text())

    def test_reviewed_workflow_passes(self):
        self.assertEqual(validate(self.document)['runnerLabels'], ['xcode-27', 'ubuntu-latest'])

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

    def test_publishing_requires_main_complete_gates_and_no_checkout(self):
        for change in ['condition', 'needs', 'checkout', 'script', 'permissions', 'environment']:
            changed = copy.deepcopy(self.document); job = changed['jobs']['publish-docs']
            if change == 'condition': job['if'] = 'always()'
            elif change == 'needs': job['needs'] = ['qualify']
            elif change == 'checkout': job['steps'].append(copy.deepcopy(changed['jobs']['qualify']['steps'][1]))
            elif change == 'script': job['steps'].append({'run': 'python3 untrusted.py'})
            elif change == 'permissions': job['permissions']['contents'] = 'write'
            else: job['environment']['name'] = 'production'
            with self.subTest(change=change), self.assertRaises(RuntimeError): validate(changed)

    def test_unpinned_actions_and_reduced_gates_are_rejected(self):
        changed = copy.deepcopy(self.document); changed['jobs']['archive']['steps'][1]['uses'] = 'actions/checkout@v6'
        with self.assertRaises(RuntimeError): validate(changed)
        changed = copy.deepcopy(self.document); changed['jobs']['qualify']['strategy']['matrix']['lane'].remove('safety')
        with self.assertRaises(RuntimeError): validate(changed)

    def test_ambiguous_yaml_and_object_construction_are_rejected(self):
        for source in ['jobs: {}\njobs: {}\n', 'a: &shared {}\nb: *shared\n', '---\na: 1\n---\nb: 2\n', 'x: !ruby/object:Object {}\n']:
            with self.subTest(source=source), self.assertRaises(RuntimeError): load_yaml(source)


if __name__ == '__main__':
    unittest.main()
