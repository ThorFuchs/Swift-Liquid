# SPDX-License-Identifier: Apache-2.0
"""Audit contribution isolation with Ruby's standard-library YAML parser.

These checks help review repository configuration. GitHub-hosted VM isolation and
repository settings remain the boundary; a PR can edit its own checkout's checks.
"""
import json
from pathlib import Path
import re
import subprocess

PARSER = r'''
require 'yaml'
require 'json'
def inspect_node(node)
  raise 'YAML aliases are not permitted' if node.is_a?(Psych::Nodes::Alias)
  if node.is_a?(Psych::Nodes::Mapping)
    keys = node.children.each_slice(2).map do |key, _|
      raise 'Only scalar YAML keys are permitted' unless key.is_a?(Psych::Nodes::Scalar)
      key.value
    end
    raise 'Duplicate YAML keys' unless keys.uniq.length == keys.length
  end
  (node.children || []).each { |child| inspect_node(child) } if node.respond_to?(:children)
end
source = STDIN.read
stream = Psych.parse_stream(source)
raise 'Exactly one YAML document required' unless stream.children.length == 1
inspect_node(stream)
document = Psych.safe_load(source, aliases: false)
if document.is_a?(Hash) && document.key?(true)
  raise 'Duplicate trigger key' if document.key?('on')
  document['on'] = document.delete(true)
end
puts JSON.generate(document)
'''

HOST_GUARD = {
    'name': 'Require GitHub-hosted isolation',
    'env': {'RUNNER_ENVIRONMENT': '${{ runner.environment }}'},
    'run': 'test "$RUNNER_ENVIRONMENT" = "github-hosted"'
}
PAGES_CONDITION = "github.ref == 'refs/heads/main' && github.event_name != 'pull_request'"


def load_yaml(text):
    result = subprocess.run(['ruby', '-e', PARSER], input=text, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Workflow YAML rejected: ' + result.stderr.strip())
    return json.loads(result.stdout)


def validate(document):
    if not isinstance(document, dict):
        raise RuntimeError('Workflow must be a mapping')
    triggers = document.get('on')
    if not isinstance(triggers, dict) or set(triggers) != {'push', 'pull_request', 'workflow_dispatch'}:
        raise RuntimeError('Only push, pull_request and manual triggers are permitted')
    if triggers['push'] != {'branches': ['main']} or triggers['pull_request'] is not None or triggers['workflow_dispatch'] is not None:
        raise RuntimeError('Unexpected trigger configuration')
    if document.get('permissions') != {'contents': 'read'}:
        raise RuntimeError('Workflow defaults must be contents: read')
    jobs = document.get('jobs', {})
    if set(jobs) != {'qualify', 'matched-performance', 'archive', 'publish-docs'}:
        raise RuntimeError('Review changed job membership')
    if jobs['qualify'].get('strategy', {}).get('matrix') != {'lane': ['native', 'safety', 'docs', 'performance', 'reference', 'platforms', 'installation']}:
        raise RuntimeError('Qualification lanes must remain complete')
    if jobs['matched-performance'].get('needs') != 'qualify' or jobs['archive'].get('needs') != ['qualify', 'matched-performance']:
        raise RuntimeError('Archive must follow complete qualification and matched evidence')
    for name, job in jobs.items():
        expected_runner = 'ubuntu-latest' if name == 'publish-docs' else 'xcode-27'
        if job.get('runs-on') != expected_runner:
            raise RuntimeError('Only the reviewed GitHub-hosted image labels are permitted')
        if job.get('steps', [None])[0] != HOST_GUARD:
            raise RuntimeError('Hosted-runner admission must precede checkout or execution')
        if name != 'publish-docs':
            if job.get('permissions', {'contents': 'read'}) != {'contents': 'read'} or 'environment' in job:
                raise RuntimeError('Qualification cannot receive publishing permissions/environments')
            if job.get('env', {}).get('LIQUID_RUNNER_ENVIRONMENT') != '${{ runner.environment }}':
                raise RuntimeError('Qualification must retain actual runner provenance')
        else:
            if job.get('if') != PAGES_CONDITION or job.get('needs') != ['qualify', 'archive']:
                raise RuntimeError('Pages must depend on qualified main-only artifacts')
            if job.get('permissions') != {'contents': 'read', 'pages': 'write', 'id-token': 'write'}:
                raise RuntimeError('Unexpected publishing permissions')
            if job.get('environment', {}).get('name') != 'github-pages':
                raise RuntimeError('Pages must use its dedicated environment')
        for step in job['steps']:
            action = step.get('uses')
            if name == 'publish-docs' and step != HOST_GUARD and (not action or action.split('@')[0] not in ['actions/configure-pages', 'actions/deploy-pages']):
                raise RuntimeError('Pages job may only configure and deploy qualified artifacts')
            if action:
                if not re.fullmatch(r'(actions/[a-z-]+|ruby/setup-ruby)@[0-9a-f]{40}', action):
                    raise RuntimeError('Actions must use reviewed repositories and full commit pins')
                allowed = {'actions/checkout', 'actions/upload-artifact', 'actions/download-artifact', 'actions/upload-pages-artifact', 'actions/configure-pages', 'actions/deploy-pages', 'ruby/setup-ruby'}
                if action.split('@')[0] not in allowed:
                    raise RuntimeError('Action repository is outside the reviewed allowlist')
                if action.startswith('actions/checkout@'):
                    if name == 'publish-docs' or step.get('with') != {'persist-credentials': False}:
                        raise RuntimeError('Checkout must not persist credentials or override the event ref')
    serialized = json.dumps(document)
    for forbidden in ['secrets', 'github.event.pull_request.head', 'workflow_run', 'pull_request_target', 'secrets: inherit']:
        if forbidden in serialized:
            raise RuntimeError('Untrusted content or credentials cross a qualification boundary')
    return {'schemaVersion': 1, 'jobs': len(jobs), 'runnerLabels': ['xcode-27', 'ubuntu-latest'],
            'event': 'pull_request', 'forkApprovalIsSandbox': False, 'sharedCaches': False}


def audit(path):
    return validate(load_yaml(Path(path).read_text()))
