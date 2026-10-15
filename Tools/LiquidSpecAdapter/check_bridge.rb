# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Negative integration probe: use a real disposable subprocess, never a Liquid fixture.
require 'tmpdir'
require 'rbconfig'
require 'stringio'
require_relative 'adapter'

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
        {template_id: 'new-process-template'}
      when 'render'
        kind = request.fetch('params').fetch('environment').fetch('kind')
        case kind
        when 'raise' then {output: nil, error: {type: 'render_error', message: 'probe error', line: 2}}
        when 'domain' then {output: nil, error: {type: 'domain_error', message: 'probe domain'}}
        when 'quota' then {output: nil, error: {type: 'operational_error', message: 'probe quota'}}
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
  options = {registers: {current_time: Time.utc(2024)}, strict_errors: true}
  error = expect_error.call(LQ1::RenderError) { bridge.render(id, {'kind' => 'raise'}, options) }
  assert.call(error.line == 2 && bridge.observed == 'render-error', 'Raised result.error lost type/location')
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
puts JSON.generate(checks: checks, status: 'passed', scope: 'negative bridge integration; no conformance cases')
