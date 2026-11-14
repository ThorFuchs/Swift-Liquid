# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Negative integration probe: use a real disposable subprocess, never a Liquid fixture.
require 'tmpdir'
require 'rbconfig'
require 'stringio'
require_relative 'adapter'
require_relative 'admission'

checks = 0
assert = ->(condition, message) { raise message unless condition; checks += 1 }
expect_error = lambda do |type, &block|
  begin
    block.call
  rescue type => error
    checks += 1
    next error
  end
  raise "Expected #{type}; an error was converted to success"
end
Dir.mktmpdir('lq1-bridge-probe-') do |directory|
  server = File.join(directory, 'server.rb')
  marker = File.join(directory, 'crashed-once')
  File.write(server, "#!#{RbConfig.ruby}\n" + <<~'SERVER')
    require 'json'
    STDOUT.sync = true
    STDIN.each_line do |line|
      request = JSON.parse(line)
      break if request['method'] == 'quit'
      result = case request['method']
      when 'initialize' then {version: '1.0', features: []}
      when 'compile'
        unless File.exist?(ENV.fetch('LQ1_BRIDGE_PROBE_MARKER'))
          File.write(ENV.fetch('LQ1_BRIDGE_PROBE_MARKER'), 'failed case must stay failed')
          exit 7
        end
        if request.fetch('params').fetch('template') == 'syntax-probe'
          {template_id: nil, error: {type: 'syntax_error', message: 'root syntax', line: 1}}
        else
          {template_id: 'new-process-template'}
        end
      when 'render'
        kind = request.fetch('params').fetch('environment').fetch('kind')
        case kind
        when 'raise' then {output: nil, error: {type: 'render_error', message: 'probe error', line: 2}}
        when 'domain' then {output: nil, error: {type: 'domain_error', message: 'probe domain'}}
        when 'quota' then {output: nil, error: {type: 'operational_error', message: 'probe quota'}}
        when 'partial-syntax' then {output: nil, error: {type: 'syntax_error', message: 'partial syntax', line: 2}}
        else {output: 'recovered', errors: [{type: 'render_error', message: 'probe recovered', line: 3}]}
        end
      end
      puts JSON.generate(jsonrpc: '2.0', id: request.fetch('id'), result: result)
    end
  SERVER
  File.chmod(0o700, server)
  ENV['LQ1_BRIDGE_PROBE_MARKER'] = marker
  trace = StringIO.new
  bridge = LQ1::Bridge.new(server, trace)
  expect_error.call(LQ1::OperationalError) { bridge.compile('probe', {}) }
  assert.call(bridge.observed == 'operational-error', 'Crash outcome was hidden')
  id = bridge.compile('probe', {})
  assert.call(id == 'new-process-template', 'Next compile did not recover a fresh subprocess')
  error = expect_error.call(LQ1::SyntaxError) { bridge.compile('syntax-probe', {}) }
  assert.call(error.line == 1 && bridge.observed == 'parse-error' && bridge.detail['type'] == 'syntax_error', 'Root syntax phase or family changed')
  options = {registers: {current_time: Time.utc(2024)}, strict_errors: true}
  error = expect_error.call(LQ1::RenderError) { bridge.render(id, {'kind' => 'raise'}, options) }
  assert.call(error.line == 2 && bridge.observed == 'render-error', 'Raised result.error lost type/location')
  error = expect_error.call(LQ1::SyntaxError) { bridge.render(id, {'kind' => 'partial-syntax'}, options) }
  assert.call(error.line == 2 && bridge.observed == 'render-error' && bridge.detail['type'] == 'syntax_error', 'Partial syntax phase or family changed')
  expect_error.call(LQ1::DomainError) { bridge.render(id, {'kind' => 'domain'}, options) }
  assert.call(bridge.observed == 'domain-divergence', 'Domain error became output')
  expect_error.call(LQ1::OperationalError) { bridge.render(id, {'kind' => 'quota'}, options) }
  assert.call(bridge.observed == 'operational-error', 'Quota became a language success')
  assert.call(bridge.render(id, {'kind' => 'inline'}, options.merge(strict_errors: false)) == 'recovered', 'Recovered output changed')
  assert.call(bridge.observed == 'recovered-error' && bridge.detail.size == 1, 'Recovered diagnostics lost')
  bridge.shutdown
  events = trace.string.lines.map { |line| JSON.parse(line) }
  assert.call(events.count { |event| event.dig('message', 'method') == 'initialize' } == 2, 'Failed case was retried or process not restarted')
  assert.call(events.last.values_at('direction', 'exitCode') == ['process-exit', 0], 'Quit was not clean')
ensure
  ENV.delete('LQ1_BRIDGE_PROBE_MARKER')
end
spec = Struct.new(:template, :raw_filesystem, :raw_template_factory, :raw_resource_limits, :raw_environment, :render_errors, :errors).new('hello', {'_error-message' => 'missing'}, nil, {}, {}, false, {})
fs = [:unused_filesystem_callback, 'digest']
assert.call(LQ1::Admission.check(fs, spec, 'digest', []) == :unused_filesystem_callback, 'Unrelated callback was not admitted')
spec.template = "{% render 'x' %}"
expect_error.call(RuntimeError) { LQ1::Admission.check(fs, spec, 'digest', []) }
spec.template = 'hello'; spec.raw_filesystem['child'] = "{% include 'x' %}"
expect_error.call(RuntimeError) { LQ1::Admission.check(fs, spec, 'digest', []) }
spec.raw_filesystem.delete('child'); spec.raw_resource_limits = {'render_score_limit' => 1}
expect_error.call(RuntimeError) { LQ1::Admission.check(fs, spec, 'digest', []) }
spec.raw_resource_limits = {}
expect_error.call(RuntimeError) { LQ1::Admission.check(fs, spec, 'changed', []) }
range = [:unused_resource_limits, 'digest']
assert.call(LQ1::Admission.check(range, spec, 'digest', LQ1::Admission::RESOURCE_FEATURES) == :unused_resource_limits, 'Metadata-only case was not admitted')
expect_error.call(RuntimeError) { LQ1::Admission.check(range, spec, 'digest', LQ1::Admission::RESOURCE_FEATURES + [:drops]) }
spec.raw_resource_limits = {'render_score_limit' => 1}
expect_error.call(RuntimeError) { LQ1::Admission.check(range, spec, 'digest', LQ1::Admission::RESOURCE_FEATURES) }
spec.raw_resource_limits = {}; spec.template = LQ1::Admission::COMMENT_TEMPLATE
spec.raw_filesystem = {'_error-message' => 'This liquid context does not allow includes.'}
comment = [:comment_only_filesystem_callback, 'digest']
assert.call(LQ1::Admission.check(comment, spec, 'digest', []) == :comment_only_filesystem_callback, 'Comment-only callback case was not admitted')
spec.template += "{% render 'x' %}"
expect_error.call(RuntimeError) { LQ1::Admission.check(comment, spec, 'digest', []) }
spec.raw_filesystem = {}; spec.raw_environment = {'long_string' => {'instantiate:LongString' => {'length' => 100_000}}}
def spec.instantiate_environment = {'long_string' => 'X' * 100_000}
long = [:materialized_long_string, 'digest']
assert.call(LQ1::Admission.check(long, spec, 'digest', [:ruby_drops]) == :materialized_long_string, 'Exact materialized string was not admitted')
def spec.instantiate_environment = {'long_string' => 'Y' * 100_000}
expect_error.call(RuntimeError) { LQ1::Admission.check(long, spec, 'digest', [:ruby_drops]) }
def spec.instantiate_environment = {'long_string' => 'X' * 100_000}
spec.raw_environment['long_string']['instantiate:LongString']['length'] = 100_001
expect_error.call(RuntimeError) { LQ1::Admission.check(long, spec, 'digest', [:ruby_drops]) }
spec.raw_environment = {}; spec.render_errors = true; spec.errors = {'output' => ['not found']}
diagnostic = [:missing_file_diagnostics, 'digest']
assert.call(LQ1::Admission.check(diagnostic, spec, 'digest', [:shopify_error_format]) == :missing_file_diagnostics, 'Portable diagnostic case was not admitted')
expect_error.call(RuntimeError) { LQ1::Admission.check(diagnostic, spec, 'digest', [:shopify_error_format, :drops]) }
spec.raw_filesystem = {'_error-message' => 'custom'}
expect_error.call(RuntimeError) { LQ1::Admission.check(diagnostic, spec, 'digest', [:shopify_error_format]) }
spec.raw_filesystem = {}; spec.render_errors = false
expect_error.call(RuntimeError) { LQ1::Admission.check(diagnostic, spec, 'digest', [:shopify_error_format]) }
puts JSON.generate(checks: checks, status: 'passed', scope: 'negative bridge integration; no conformance cases')
