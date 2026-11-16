#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Run only the three pinned fixed NumberDrop fixtures; never invoke SpecLoader.
ENV['BUNDLE_GEMFILE'] = File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'json'
require 'yaml'
require 'digest'
require 'time'
require 'liquid'
require 'active_support/all'
require 'liquid/spec'
require 'liquid/spec/deps/liquid_ruby'
require 'liquid/spec/deps/standard_drops'
require_relative 'adapter'

module LQ1::ForbidIndexDynamicEval
  def eval(*)
    raise SecurityError, 'Dynamic Ruby evaluation is forbidden during NumberDrop qualification'
  end
end
Binding.prepend(LQ1::ForbidIndexDynamicEval)
Kernel.prepend(LQ1::ForbidIndexDynamicEval)
Kernel.singleton_class.prepend(LQ1::ForbidIndexDynamicEval)
[-> { binding.eval('nil') }, -> { Kernel.eval('nil') }, -> { eval('nil') }].each do |probe|
  begin
    probe.call
    raise 'Dynamic evaluation guard did not engage'
  rescue SecurityError
    # These benign probes must fail before evaluating the strings.
  end
end

binary, spec_root, output = ARGV
raise 'Usage: check_number_drop.rb BINARY SPEC_ROOT OUTPUT' unless output
policy = JSON.parse(File.read(File.join(__dir__, 'NumberDropCases.json')))
expected = [{'name' => 'drop_number_renders', 'line' => 72}, {'name' => 'drop_number_works_with_filters', 'line' => 85}, {'name' => 'drop_number_zero_is_truthy', 'line' => 101}]
raise 'Candidate identities changed' unless policy.fetch('cases') == expected
path = File.join(spec_root, policy.fetch('fixture'))
raise 'Fixture hash changed' unless Digest::SHA256.file(path).hexdigest == policy.fetch('fixtureSHA256')
raise 'Wrong reference or suite version' unless Liquid::VERSION == '5.14.0' && Liquid::Spec::VERSION == '2.0.0'
raise 'Unexpected NumberDrop registry' unless Liquid::Spec::ClassRegistry.instantiate('NumberDrop', {'value' => 42}).instance_of?(StandardNumberDrop)
content = File.binread(path)
fixtures = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false).fetch('specs')
lines = content.lines
rows = []
File.open(output + '.trace.jsonl', 'w') do |trace|
  bridge = LQ1::Bridge.new(binary, trace)
  swift = Liquid::Spec::AdapterRunner.new(name: 'Swift-Liquid NumberDrop')
  swift.on_setup { |_ctx| }
  swift.on_compile { |ctx, source, opts| ctx[:id] = bridge.compile(source, opts) }
  swift.on_render { |ctx, assigns, opts| bridge.render(ctx.fetch(:id), assigns, opts) }
  swift.ensure_setup!
  reference = Liquid::Spec::AdapterRunner.new(name: 'Pinned Ruby Liquid')
  reference.on_setup { |_ctx| }
  reference.on_compile { |ctx, source, opts| ctx[:template] = Liquid::Template.parse(source, **opts) }
  reference.on_render do |ctx, assigns, opts|
    context = Liquid::Context.build(static_environments: assigns,
      registers: Liquid::Registers.new(opts.fetch(:registers)), rethrow_errors: opts.fetch(:strict_errors))
    ctx.fetch(:template).render(context)
  end
  reference.ensure_setup!
  begin
    Liquid::Spec::TimeFreezer.freeze_spec_time do
      policy.fetch('cases').each do |item|
        name, line = item.values_at('name', 'line')
        raise 'Fixture line changed' unless lines.fetch(line - 1).strip == "- name: #{name}"
        matches = fixtures.select { |fixture| fixture['name'] == name }
        raise 'Fixture identity changed' unless matches.size == 1
        fixture = matches.fetch(0)
        unless !fixture.key?('generate') && fixture['environment'].is_a?(Hash) && fixture['environment'].size == 1 &&
               fixture['environment'].values.first.is_a?(Hash) && fixture['environment'].values.first.keys == ['instantiate:NumberDrop'] &&
               fixture['environment'].values.first.values.first.is_a?(Hash) && fixture['environment'].values.first.values.first.keys == ['value'] &&
               fixture['environment'].values.first.values.first['value'].is_a?(Integer) &&
               fixture['features'] == ['drops'] && fixture['template'].is_a?(String) && fixture['expected'].is_a?(String)
          raise 'Unsafe or changed fixed fixture contract'
        end
        spec = Liquid::Spec::LazySpec.new(name: name, template: fixture.fetch('template'), expected: fixture.fetch('expected'),
          error_mode: :strict2, features: [:drops], raw_environment: fixture.fetch('environment'), raw_filesystem: nil,
          source_file: path, line_number: line)
        id = "basics/#{policy.fetch('fixture')}:#{line}/#{name}/strict2/raise"
        bridge.case_key = id
        swift_result = swift.run_single(spec)
        reference_result = reference.run_single(spec)
        rows << {caseID: id, sourceDigest: policy.fetch('fixtureSHA256'), parserMode: 'strict2', renderMode: 'raise',
          expected: fixture.fetch('expected'), swift: {passed: swift_result.passed?, status: swift_result.status, output: swift_result.output},
          reference: {passed: reference_result.passed?, status: reference_result.status, output: reference_result.output}}
      end
    end
  ensure
    bridge.shutdown
  end
end
matched = rows.count { |row| row[:swift][:passed] && row[:reference][:passed] }
passed = rows.size == 3 && matched == 3
report = {status: passed ? 'passed' : 'failed', scope: 'three fixed pinned NumberDrop cases; upstream comparator; no fixture expression evaluation',
          specPin: policy.fetch('specPin'), referencePin: policy.fetch('referencePin'), fixtureSHA256: policy.fetch('fixtureSHA256'),
          rubyVersion: RUBY_DESCRIPTION, liquidVersion: Liquid::VERSION, suiteVersion: Liquid::Spec::VERSION,
          dynamicEvaluationGuard: 'enabled', selectedCases: rows.size, matchedCases: matched, cases: rows}
File.write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
exit(passed ? 0 : 1)
