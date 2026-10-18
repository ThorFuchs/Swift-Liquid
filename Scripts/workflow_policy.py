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
    'run': 'test "$RUNNER_ENVIRONMENT" = "github-hosted"\n'
           'echo "LIQUID_RUNNER_ENVIRONMENT=$RUNNER_ENVIRONMENT" >> "$GITHUB_ENV"\n'
}
MAIN_DISPATCH = "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'"
LANES = ['native', 'safety', 'docs', 'reference', 'platforms', 'installation']
PINS = {
    'actions/checkout': 'd23441a48e516b6c34aea4fa41551a30e30af803',
    'actions/upload-artifact': 'b7c566a772e6b6bfb58ed0dc250532a479d7789f',
    'actions/download-artifact': '37930b1c2abaa49bbe596cd826c3c89aef350131',
    'actions/upload-pages-artifact': 'fc324d3547104276b827a68afc52ff2a11cc49c9',
    'actions/configure-pages': '45bfe0192ca1faeb007ade9deae92b16b8254a0d',
    'actions/deploy-pages': '368f82528645a54fb793d4d04e342629a3f51346',
    'ruby/setup-ruby': '651ff0d62c5c79bed6d53ec518387aae20e72c1a',
}
AGGREGATE_RUN = '''python3 - <<'PY'
import json, os
needs = json.loads(os.environ['NEEDS_JSON'])
if set(needs) != {'qualify', 'archive'} or any(
    needs[name].get('result') != 'success' for name in needs
):
    raise SystemExit('Every required lane and clean archive must succeed')
print('Repository correctness passed')
PY
'''


def load_yaml(text):
    result = subprocess.run(['ruby', '-e', PARSER], input=text, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Workflow YAML rejected: ' + result.stderr.strip())
    return json.loads(result.stdout)


def demand(value, message):
    if not value:
        raise RuntimeError(message)


def steps(job, kind):
    demand(isinstance(job.get('steps'), list) and job['steps'] and job['steps'][0] == HOST_GUARD,
           'Hosted-runner admission must precede checkout or execution')
    demand('uses' not in job and job.get('continue-on-error', False) is False,
           'No reusable job or tolerated required failure')
    demand(not any(step.get('continue-on-error', False) is not False for step in job['steps']),
           'No tolerated step failure')
    demand('runner.' not in json.dumps(job.get('env', {})),
           'Runner context must be exported from the first step')
    for step in job['steps']:
        action = step.get('uses')
        if action:
            name, _, pin = action.partition('@')
            demand(PINS.get(name) == pin, 'Actions must retain reviewed repositories and immutable pins')
            if name == 'actions/checkout':
                demand(kind != 'privileged' and step.get('with') == {'persist-credentials': False},
                       'Checkout cannot persist credentials or override the event source')
        demand(not any(key in step for key in ['working-directory', 'shell']),
               'Review changed command execution boundary')


def run_step(job, name, command, condition=None):
    selected = [step for step in job['steps'] if step.get('name') == name]
    demand(len(selected) == 1 and selected[0].get('run') == command
           and selected[0].get('if') == condition, 'Required command/condition changed: ' + name)
    return selected[0]


def manual_inputs(triggers, names):
    demand(isinstance(triggers, dict) and set(triggers) == {'workflow_dispatch'},
           'Controlled workflows must be manual only')
    inputs = (triggers.get('workflow_dispatch') or {}).get('inputs', {})
    demand(set(inputs) == set(names), 'Review changed dispatch inputs')
    for name in names:
        demand(inputs[name].get('required') is True and inputs[name].get('type') == 'string',
               'Explicit required string input missing')


def validate(document, kind='ci'):
    if not isinstance(document, dict):
        raise RuntimeError('Workflow must be a mapping')
    demand(set(document) == {'name', 'on', 'permissions', 'concurrency', 'jobs'},
           'Review workflow-level defaults, environment or execution substitution')
    triggers = document.get('on')
    demand(isinstance(triggers, dict), 'Workflow triggers must be a mapping')
    if document.get('permissions') != {'contents': 'read'}:
        raise RuntimeError('Workflow defaults must be contents: read')
    jobs = document.get('jobs', {})
    membership = {'ci': {'qualify', 'archive', 'correctness'}, 'benchmarks': {'benchmarks'},
                  'documentation': {'admit', 'deploy'}}
    demand(kind in membership and set(jobs) == membership[kind], 'Review changed workflow/job membership')
    for name, job in jobs.items():
        allowed = {'name', 'runs-on', 'timeout-minutes', 'steps'}
        if kind == 'ci':
            allowed |= {'qualify': {'strategy', 'env'}, 'archive': {'needs', 'env'},
                        'correctness': {'needs', 'if'}}[name]
        elif kind == 'benchmarks':
            allowed |= {'env'}
        else:
            allowed |= {'if', 'permissions'}
            if name == 'deploy': allowed |= {'needs', 'environment'}
        demand(set(job) == allowed, 'Review job defaults, environment, container or execution substitution')
        expected_env = {'DEVELOPER_DIR': '/Applications/Xcode_27.2.app/Contents/Developer', 'PYTHONDONTWRITEBYTECODE': '1'}
        if kind == 'ci' and name == 'archive': expected_env['LIQUID_SWIFTPM_FLAGS'] = '--jobs 2'
        if 'env' in allowed: demand(job['env'] == expected_env, 'Review compiler/tool/environment substitution')
        privileged = kind == 'documentation' and name == 'deploy'
        expected_runner = 'xcode-27' if kind == 'benchmarks' or (kind == 'ci' and name != 'correctness') else 'ubuntu-latest'
        if job.get('runs-on') != expected_runner:
            raise RuntimeError('Only the reviewed GitHub-hosted image labels are permitted')
        steps(job, 'privileged' if privileged else 'read-only')
        if not privileged:
            allowed = {'contents': 'read', 'actions': 'read'} if kind == 'documentation' else {'contents': 'read'}
            if job.get('permissions', {'contents': 'read'}) != allowed or 'environment' in job:
                raise RuntimeError('Qualification cannot receive publishing permissions/environments')
        else:
            if job.get('permissions') != {'contents': 'read', 'pages': 'write', 'id-token': 'write'}:
                raise RuntimeError('Unexpected publishing permissions')
            if job.get('environment', {}).get('name') != 'github-pages':
                raise RuntimeError('Pages must use its dedicated environment')
    serialized = json.dumps(document)
    for forbidden in ['secrets', 'github.event.pull_request.head', 'workflow_run', 'pull_request_target', 'secrets: inherit']:
        if forbidden in serialized:
            raise RuntimeError('Untrusted content or credentials cross a qualification boundary')
    if kind == 'ci':
        demand(isinstance(triggers, dict) and set(triggers) == {'push', 'pull_request', 'workflow_dispatch'}
               and triggers['push'] == {'branches': ['main']} and triggers['pull_request'] is None
               and triggers['workflow_dispatch'] is None, 'Correctness events must remain complete without path filters')
        q, a, c = (jobs[name] for name in ['qualify', 'archive', 'correctness'])
        demand(q.get('strategy') == {'fail-fast': False, 'matrix': {'lane': LANES}}, 'All six correctness lanes required')
        demand('if' not in q and 'if' not in a and 'needs' not in q and a.get('needs') == 'qualify',
               'Correctness/archive cannot be conditionally skipped or depend on timing')
        demand(c.get('name') == 'Repository correctness' and c.get('if') == 'always()'
               and c.get('needs') == ['qualify', 'archive'] and len(c['steps']) == 2,
               'Fail-closed always-run aggregate required')
        step = run_step(c, 'Admit every required result', AGGREGATE_RUN)
        demand(step.get('env') == {'NEEDS_JSON': '${{ toJSON(needs) }}'}, 'Aggregate must use actual dependency results')
        run_step(q, 'Qualify', "env LIQUID_SWIFTPM_FLAGS='--jobs 2' python3 -B Scripts/ci.py --lane '${{ matrix.lane }}'",
                 "matrix.lane != 'reference' && matrix.lane != 'docs'")
        run_step(q, 'Qualify documentation', 'env -u LIQUID_SWIFTPM_FLAGS python3 -B Scripts/ci.py --lane docs', "matrix.lane == 'docs'")
        run_step(q, 'Qualify reference behavior', 'python3 -B Scripts/ci.py --lane reference --reference-path "$LIQUID_REFERENCE_PATH"', "matrix.lane == 'reference'")
        demand(len(q['steps']) == 8 and [step.get('name') for step in q['steps']] == [
            HOST_GUARD['name'], None, 'Set up pinned Ruby reference runtime', 'Prepare pinned reference',
            'Qualify', 'Qualify documentation', 'Qualify reference behavior', 'Retain qualification evidence'],
            'Review changed correctness execution steps')
        demand(q['steps'][2].get('if') == "matrix.lane == 'reference'"
               and q['steps'][2].get('with') == {'ruby-version': '4.0.1'}, 'Pinned Ruby setup changed')
        demand(q['steps'][3].get('if') == "matrix.lane == 'reference'"
               and q['steps'][3].get('run') == '''gem install date --version 3.5.1 --no-document
gem install time --version 0.4.2 --no-document
git init "$LIQUID_REFERENCE_PATH"
git -C "$LIQUID_REFERENCE_PATH" remote add origin https://github.com/Shopify/liquid.git
git -C "$LIQUID_REFERENCE_PATH" fetch --depth 1 origin 4e39ae4cc3da73921923c0669e0fc84a66b2f696
git -C "$LIQUID_REFERENCE_PATH" checkout --detach FETCH_HEAD
''', 'Reference pin/runtime acquisition changed')
        artifact = q['steps'][-1]
        demand(artifact.get('if') == 'always()' and artifact.get('with') == {
            'name': 'liquid-${{ matrix.lane }}',
            'path': 'Artifacts/${{ matrix.lane }}/\n!Artifacts/docs/Liquid.doccarchive/**\n!Artifacts/docs/site/**\n',
            'if-no-files-found': 'error', 'retention-days': 30,
            'include-hidden-files': "${{ matrix.lane == 'docs' }}"}, 'Complete bounded lane/site evidence required')
        checkout = {'uses': 'actions/checkout@' + PINS['actions/checkout'], 'with': {'persist-credentials': False}}
        demand(q['steps'][1] == checkout and q['steps'][2] == {
            'name': 'Set up pinned Ruby reference runtime', 'if': "matrix.lane == 'reference'",
            'uses': 'ruby/setup-ruby@' + PINS['ruby/setup-ruby'], 'with': {'ruby-version': '4.0.1'}},
            'Only credential-free checkout and uncached pinned Ruby setup permitted')
        demand(set(q['steps'][3]) == {'name', 'if', 'env', 'run'}
               and q['steps'][3]['env'] == {'LIQUID_REFERENCE_PATH': '${{ runner.temp }}/shopify-liquid'}, 'Reference environment changed')
        for index in [4, 5]: demand(set(q['steps'][index]) == {'name', 'if', 'run'}, 'Review qualification step substitution')
        demand(set(q['steps'][6]) == {'name', 'if', 'env', 'run'} and q['steps'][6]['env'] == {
            'LIQUID_REFERENCE_PATH': '${{ runner.temp }}/shopify-liquid', 'LIQUID_SWIFTPM_FLAGS': '--jobs 2'}, 'Reference invocation environment changed')
        demand(set(artifact) == {'name', 'if', 'uses', 'with'}
               and artifact['uses'] == 'actions/upload-artifact@' + PINS['actions/upload-artifact'], 'Lane evidence action changed')
        demand(a.get('name') == 'Qualify clean source archive'
               and a.get('env', {}).get('LIQUID_SWIFTPM_FLAGS') == '--jobs 2', 'Clean archive identity/environment changed')
        demand([step.get('run') for step in a['steps'] if 'run' in step] == [HOST_GUARD['run'], 'python3 -B Scripts/ci.py --lane archive'],
               'Archive must execute the full unchanged strict lane')
        downloads = [step for step in a['steps'] if step.get('uses', '').startswith('actions/download-artifact@')]
        demand(len(downloads) == 1 and downloads[0].get('with') == {'name': 'liquid-docs', 'path': 'Artifacts/docs'},
               'Archive must consume its own run documentation')
        demand(a['steps'] == [HOST_GUARD, checkout,
            {'uses': 'actions/download-artifact@' + PINS['actions/download-artifact'], 'with': {'name': 'liquid-docs', 'path': 'Artifacts/docs'}},
            {'run': 'python3 -B Scripts/ci.py --lane archive'},
            {'name': 'Retain correctness archive assets', 'if': 'always()',
             'uses': 'actions/upload-artifact@' + PINS['actions/upload-artifact'], 'with': {
                 'name': 'liquid-archive', 'path': 'Artifacts/archive/', 'if-no-files-found': 'error', 'retention-days': 30}}],
            'Strict archive has a closed uncached action/command/evidence graph')
        demand(set(c['steps'][1]) == {'name', 'env', 'run'}, 'Aggregate execution boundary changed')
        demand(document['concurrency'] == {'group': 'liquid-${{ github.workflow }}-${{ github.ref }}', 'cancel-in-progress': True},
               'Correctness cancellation policy changed')
        demand(not any(word in serialized for word in ['performance', 'deploy-pages', 'configure-pages', 'upload-pages-artifact', 'github.token']),
               'Routine correctness cannot run timing, publish or receive an API token')
    elif kind == 'benchmarks':
        inputs = (triggers or {}).get('workflow_dispatch', {}).get('inputs', {})
        strings = {name: value for name, value in inputs.items() if name != 'confirmation'}
        manual_inputs({'workflow_dispatch': {'inputs': strings}}, ['source_commit', 'commission_record'])
        demand(set(triggers) == {'workflow_dispatch'} and set(inputs) == {'source_commit', 'commission_record', 'confirmation'}
               and inputs['confirmation'] == {'description': 'Dispatch does not itself approve timing or performance',
                   'required': True, 'type': 'choice', 'default': 'Not commissioned',
                   'options': ['Not commissioned', 'Separate timing commission approved']}, 'Explicit timing confirmation required')
        b = jobs['benchmarks']
        demand('if' not in b and 'needs' not in b and len(b['steps']) == 7, 'Review controlled benchmark graph')
        bind = next((step for step in b['steps'] if step.get('name') == 'Bind commissioned source'), {})
        demand(bind.get('env') == {'SOURCE_COMMIT': '${{ inputs.source_commit }}',
                'COMMISSION_RECORD': '${{ inputs.commission_record }}', 'CONFIRMATION': '${{ inputs.confirmation }}'},
               'Bind dispatch data through environment, never shell interpolation')
        run_step(b, 'Bind commissioned source', 'python3 -B Scripts/benchmark_request.py')
        run_step(b, 'Prepare immutable baseline', 'git fetch --no-tags --depth 1 origin 9963591f18ef8aa1d1a8d9cd9bcc5508c82b5d4e')
        run_step(b, 'Measure candidate', 'env -u LIQUID_SWIFTPM_FLAGS python3 -B Scripts/ci.py --lane performance')
        run_step(b, 'Measure matched comparison', 'env -u LIQUID_SWIFTPM_FLAGS python3 -B Scripts/ci.py --lane matched-performance')
        names = [step.get('name') for step in b['steps']]
        demand(names.index('Bind commissioned source') < names.index('Prepare immutable baseline') < names.index('Measure candidate') < names.index('Measure matched comparison'),
               'Benchmark admission and launches must remain serial')
        demand(document.get('concurrency') == {'group': 'liquid-controlled-benchmarks', 'cancel-in-progress': False},
               'Do not overlap or cancel controlled measurements')
        demand(b['steps'][1] == {'uses': 'actions/checkout@' + PINS['actions/checkout'], 'with': {'persist-credentials': False}}
               and set(bind) == {'name', 'env', 'run'}, 'Controlled source checkout/binding changed')
        for index in [3, 4, 5]: demand(set(b['steps'][index]) == {'name', 'run'}, 'Measurement step substitution')
        demand(b['steps'][-1] == {'name': 'Retain every measurement', 'if': 'always()',
            'uses': 'actions/upload-artifact@' + PINS['actions/upload-artifact'], 'with': {
                'name': 'liquid-controlled-benchmarks', 'path': 'Artifacts/benchmark-request.json\nArtifacts/performance/\nArtifacts/matched-performance/\n',
                'if-no-files-found': 'error', 'retention-days': 30}}, 'Complete measurement preservation required')
    else:
        manual_inputs(triggers, ['correctness_run_id', 'main_commit', 'approval_record'])
        admit, deploy = jobs['admit'], jobs['deploy']
        demand(admit.get('if') == MAIN_DISPATCH and deploy.get('if') == MAIN_DISPATCH
               and 'needs' not in admit and deploy.get('needs') == 'admit', 'Pages requires explicit admitted main dispatch')
        demand(len(admit['steps']) == 5 and len(deploy['steps']) == 3, 'Review documentation admission/deployment graph')
        step = run_step(admit, 'Verify run, source and artifact', 'python3 -B Scripts/documentation_admission.py --run-id "$CORRECTNESS_RUN_ID" --commit "$MAIN_COMMIT" --approval-record "$APPROVAL_RECORD" --output "$RUNNER_TEMP/liquid-docs-admission"')
        demand(step.get('env') == {'GH_TOKEN': '${{ github.token }}', 'CORRECTNESS_RUN_ID': '${{ inputs.correctness_run_id }}',
               'MAIN_COMMIT': '${{ inputs.main_commit }}', 'APPROVAL_RECORD': '${{ inputs.approval_record }}'}, 'Unbound documentation request')
        demand(set(step) == {'name', 'env', 'run'} and admit['steps'][1] == {
            'uses': 'actions/checkout@' + PINS['actions/checkout'], 'with': {'persist-credentials': False}}, 'Read-only admission source changed')
        demand(admit['steps'][3] == {'name': 'Retain admission evidence', 'if': 'always()',
            'uses': 'actions/upload-artifact@' + PINS['actions/upload-artifact'], 'with': {
                'name': 'liquid-documentation-admission', 'path': '${{ runner.temp }}/liquid-docs-admission/admission.json',
                'if-no-files-found': 'error', 'retention-days': 30}}, 'Complete admission preservation required')
        demand([step.get('uses') for step in deploy['steps'][1:]] == ['actions/configure-pages@' + PINS['actions/configure-pages'], 'actions/deploy-pages@' + PINS['actions/deploy-pages']],
               'Privileged Pages job may only configure/deploy; no checkout or source/artifact execution')
        demand(deploy['steps'][1] == {'uses': 'actions/configure-pages@' + PINS['actions/configure-pages']}
               and deploy['steps'][2] == {'id': 'deployment', 'uses': 'actions/deploy-pages@' + PINS['actions/deploy-pages']},
               'No alternate privileged artifact, ref, token or command')
        pages = admit['steps'][-1]
        demand(pages.get('uses') == 'actions/upload-pages-artifact@' + PINS['actions/upload-pages-artifact']
               and pages.get('with') == {'path': '${{ runner.temp }}/liquid-docs-admission/site', 'include-hidden-files': True}
               and 'if' not in pages, 'Only successful admitted site can become Pages artifact')
        demand(set(pages) == {'name', 'uses', 'with'} and deploy['environment'] == {
            'name': 'github-pages', 'url': '${{ steps.deployment.outputs.page_url }}'}, 'Pages execution boundary changed')
        demand(document['concurrency'] == {'group': 'github-pages', 'cancel-in-progress': False}, 'Pages publication must remain serial')
    return {'schemaVersion': 2, 'kind': kind, 'jobs': len(jobs), 'runnerLabels': sorted({job['runs-on'] for job in jobs.values()}, reverse=True),
            'forkApprovalIsSandbox': False, 'sharedCaches': False, 'routineTiming': False, 'routineDeployment': False}


def audit(path):
    root = Path(path).parent
    expected = {'ci.yml': 'ci', 'benchmarks.yml': 'benchmarks', 'documentation.yml': 'documentation'}
    demand({p.name for p in root.iterdir() if p.is_file()} == set(expected), 'Review the complete workflow closure')
    demand(not any(p.is_symlink() or not p.is_file() for p in root.iterdir()), 'Only declared regular workflow files permitted')
    return {name: validate(load_yaml((root / name).read_text()), kind) for name, kind in expected.items()}
