#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Qualify only five hash-bound fixtures with Shopify's actual comparator.
# Do not call SpecLoader: it evaluates generated fixture expressions.
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
require_relative 'method_drop_materializer'

# Defense in depth: even an accidental upstream Binding#eval or Kernel.eval
# call must fail this isolated qualification instead of executing fixture text.
module LQ1::ForbidDynamicEval
  def eval(*)
    raise SecurityError, 'Dynamic Ruby evaluation is forbidden during MethodDrop qualification'
  end
end
Binding.prepend(LQ1::ForbidDynamicEval)
Kernel.prepend(LQ1::ForbidDynamicEval)
Kernel.singleton_class.prepend(LQ1::ForbidDynamicEval)
[-> { binding.eval('nil') }, -> { Kernel.eval('nil') }, -> { eval('nil') }].each do |probe|
  begin
    probe.call
    raise 'Dynamic evaluation guard did not engage'
  rescue SecurityError
    # Benign probes verify the guards without executing the strings.
  end
end

binary, spec_root, output = ARGV
raise 'Usage: check_method_drop.rb BINARY SPEC_ROOT OUTPUT' unless output
policy = JSON.parse(File.read(File.join(__dir__, 'MethodDropCases.json')))
expected_fixed = [{'name' => 'drop_method_echo', 'line' => 143}, {'name' => 'drop_method_square', 'line' => 154}, {'name' => 'drop_method_double', 'line' => 164}]
expected_generated = [{'name' => 'drop_method_square_random', 'line' => 174, 'minimum' => 1, 'maximum' => 100},
                      {'name' => 'drop_method_echo_random', 'line' => 191, 'minimum' => 1, 'maximum' => 1000}]
raise 'Candidate identities changed' unless policy.fetch('cases') == expected_fixed && policy.fetch('generatedCases') == expected_generated
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

  locate = lambda do |item|
    name, line = item.values_at('name', 'line')
    raise 'Fixture line changed' unless lines.fetch(line - 1).strip == "- name: #{name}"
    found = fixtures.select { |fixture| fixture['name'] == name }
    raise 'Fixture identity changed' unless found.size == 1
    found.fetch(0)
  end
  evaluate = lambda do |fixture, item, template, expected, number = nil|
    name, line = item.values_at('name', 'line')
    features = number.nil? ? [:drops] : [:drops, :randomness]
    spec = Liquid::Spec::LazySpec.new(name: name, template: template, expected: expected,
      error_mode: :strict2, features: features, raw_environment: fixture.fetch('environment'), raw_filesystem: nil,
      source_file: path, line_number: line)
    id = "basics/#{policy.fetch('fixture')}:#{line}/#{name}/strict2/raise"
    bridge.case_key = number.nil? ? id : "#{id}/input:#{number}"
    swift_result = swift.run_single(spec)
    ref_result = reference.run_single(spec)
    {input: number, template: template, expected: expected,
     swift: {passed: swift_result.passed?, status: swift_result.status, output: swift_result.output},
     reference: {passed: ref_result.passed?, status: ref_result.status, output: ref_result.output}}
  end
  begin
    Liquid::Spec::TimeFreezer.freeze_spec_time do
      policy.fetch('cases').each do |item|
        fixture = locate.call(item)
        unless !fixture.key?('generate') && fixture['environment'] == {'drop' => 'instantiate:MethodDrop'} &&
               fixture['features'] == ['drops'] && fixture['template'].is_a?(String) && fixture['expected'].is_a?(String)
          raise 'Unsafe or changed fixed fixture contract'
        end
        id = "basics/#{policy.fetch('fixture')}:#{item.fetch('line')}/#{item.fetch('name')}/strict2/raise"
        rows << {caseID: id, sourceDigest: policy.fetch('fixtureSHA256'), parserMode: 'strict2', renderMode: 'raise',
                 kind: 'fixed', samples: [evaluate.call(fixture, item, fixture.fetch('template'), fixture.fetch('expected'))]}
      end
      policy.fetch('generatedCases').each do |item|
        fixture = locate.call(item)
        range = LQ1::MethodDropMaterializer.bounds(fixture)
        raise 'Generated bounds changed' unless range == (item.fetch('minimum')..item.fetch('maximum'))
        id = "basics/#{policy.fetch('fixture')}:#{item.fetch('line')}/#{item.fetch('name')}/strict2/raise"
        samples = range.map do |number|
          materialized = LQ1::MethodDropMaterializer.materialize(fixture, number)
          evaluate.call(fixture, item, materialized.fetch(:template), materialized.fetch(:expected), number)
        end
        rows << {caseID: id, sourceDigest: policy.fetch('fixtureSHA256'), parserMode: 'strict2', renderMode: 'raise',
                 kind: 'generated-exhaustive', minimum: range.first, maximum: range.last, samples: samples}
      end
    end
  ensure
    bridge.shutdown
  end
end
sample_count = rows.sum { |row| row[:samples].size }
matched_cases = rows.count { |row| row[:samples].all? { |sample| sample[:swift][:passed] && sample[:reference][:passed] } }
passed = rows.size == 5 && sample_count == 1103 && matched_cases == 5
report = {status: passed ? 'passed' : 'failed', scope: 'three fixed and two generated pinned MethodDrop fixtures; exhaustive declared integer domains; upstream comparator; no fixture expression evaluation',
          specPin: policy.fetch('specPin'), referencePin: policy.fetch('referencePin'), fixtureSHA256: policy.fetch('fixtureSHA256'),
          rubyVersion: RUBY_DESCRIPTION, liquidVersion: Liquid::VERSION, suiteVersion: Liquid::Spec::VERSION, dynamicEvaluationGuard: 'enabled',
          selectedCases: rows.size, matchedCases: matched_cases, fixedSamples: 3, generatedSamples: sample_count - 3, cases: rows}
File.write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report.reject { |key, _| key == :cases })
exit(passed ? 0 : 1)
