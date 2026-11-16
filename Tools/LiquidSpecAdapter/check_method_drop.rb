#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Execute only three hash-bound fixed fixtures with Shopify's actual comparator.
# Never invoke SpecLoader: its generated-case path evaluates fixture expressions.
ENV['BUNDLE_GEMFILE'] = File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'json'
require 'yaml'
require 'digest'
require 'time'
require 'liquid'
require 'active_support/all'
require 'liquid/spec'
require 'liquid/spec/deps/standard_drops'
require_relative 'adapter'

binary, spec_root, output = ARGV
raise 'Usage: check_method_drop.rb BINARY SPEC_ROOT OUTPUT' unless output
policy = JSON.parse(File.read(File.join(__dir__, 'MethodDropCases.json')))
path = File.join(spec_root, policy.fetch('fixture'))
raise 'Fixture hash changed' unless Digest::SHA256.file(path).hexdigest == policy.fetch('fixtureSHA256')
raise 'Wrong reference or suite version' unless Liquid::VERSION == '5.14.0' && Liquid::Spec::VERSION == '2.0.0'
content = File.binread(path)
parsed = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false)
fixtures = parsed.fetch('specs')
lines = content.lines
rows = []
File.open(output + '.trace.jsonl', 'w') do |trace|
  bridge = LQ1::Bridge.new(binary, trace)
  swift = Liquid::Spec::AdapterRunner.new(name: 'Swift-Liquid MethodDrop')
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
      found = fixtures.select { |fixture| fixture['name'] == name }
      raise 'Fixture identity changed' unless found.size == 1
      fixture = found.fetch(0)
      raise 'Unsafe or changed fixture contract' unless !fixture.key?('generate') && fixture['environment'] == {'drop' => 'instantiate:MethodDrop'} && fixture['features'] == ['drops'] && fixture['template'].is_a?(String) && fixture['expected'].is_a?(String)
      spec = Liquid::Spec::LazySpec.new(name: name, template: fixture.fetch('template'), expected: fixture.fetch('expected'),
        error_mode: :strict2, features: [:drops], raw_environment: fixture.fetch('environment'), raw_filesystem: nil,
        source_file: path, line_number: line)
      id = "basics/#{policy.fetch('fixture')}:#{line}/#{name}/strict2/raise"
      bridge.case_key = id
      swift_result = swift.run_single(spec)
      ref_result = reference.run_single(spec)
      rows << {caseID: id, sourceDigest: policy.fetch('fixtureSHA256'), parserMode: 'strict2', renderMode: 'raise',
        swift: {passed: swift_result.passed?, status: swift_result.status, output: swift_result.output},
        reference: {passed: ref_result.passed?, status: ref_result.status, output: ref_result.output}, expected: fixture.fetch('expected')}
     end
    end
  ensure
    bridge.shutdown
  end
end
passed = rows.size == 3 && rows.all? { |row| row[:swift][:passed] && row[:reference][:passed] }
report = {status: passed ? 'passed' : 'failed', scope: 'three fixed pinned MethodDrop cases; upstream comparator; no generated expressions',
          specPin: policy.fetch('specPin'), referencePin: policy.fetch('referencePin'), fixtureSHA256: policy.fetch('fixtureSHA256'),
          selected: rows.size, matched: rows.count { |row| row[:swift][:passed] && row[:reference][:passed] }, cases: rows}
File.write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
exit(passed ? 0 : 1)
