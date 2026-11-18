#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Select fixed, hash-pinned YAML nodes without loading or evaluating generators.
ENV['BUNDLE_GEMFILE'] = File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'json'
require 'yaml'
require 'psych'
require 'digest'
require 'time'
require 'liquid'
require 'active_support/all'
require 'liquid/spec'
require 'liquid/spec/deps/liquid_ruby'
require 'liquid/spec/deps/standard_drops'
require_relative 'adapter'

module LQ1::ForbidSequenceDynamicEval
  def eval(*)
    raise SecurityError, 'Dynamic Ruby evaluation is forbidden during SequenceDrop qualification'
  end
end
Binding.prepend(LQ1::ForbidSequenceDynamicEval)
Kernel.prepend(LQ1::ForbidSequenceDynamicEval)
Kernel.singleton_class.prepend(LQ1::ForbidSequenceDynamicEval)
[-> { binding.eval('nil') }, -> { Kernel.eval('nil') }, -> { eval('nil') }].each do |probe|
  begin
    probe.call
    raise 'Dynamic evaluation guard did not engage'
  rescue SecurityError
    # Only these constant guard probes are evaluated.
  end
end

binary, spec_root, output = ARGV
raise 'Usage: check_sequence_drop.rb BINARY SPEC_ROOT OUTPUT' unless output
policy = JSON.parse(File.read(File.join(__dir__, 'SequenceDropCases.json')))
study = JSON.parse(File.read(File.expand_path('../../Documentation/LQ1/STANDARD-DROPS-2.1.json', __dir__)))
original = study.fetch('cases').select { |c| c.fetch('constructors').any? { |ctor| ctor.fetch('class') == 'SequenceDrop' } }
expected = original.map do |c|
  c.slice('caseID', 'sourceLocation', 'sourceDigest', 'parserMode', 'renderMode', 'featureTags').merge('name' => c.fetch('fixture').fetch('name'))
end
raise 'Candidate identities changed' unless policy.fetch('cases') == expected && expected.size == 5 && expected.map { |c| c['caseID'] }.uniq.size == 5
raise 'Wrong reference or suite version' unless Liquid::VERSION == '5.14.0' && Liquid::Spec::VERSION == '2.0.0'
instance = Liquid::Spec::ClassRegistry.instantiate('SequenceDrop', {})
raise 'Unexpected SequenceDrop registry' unless instance.instance_of?(StandardSequenceDrop) && instance.to_a == %w[first second third]
root = File.realpath(spec_root)
files = {}
rows = []
File.open(output + '.trace.jsonl', 'w') do |trace|
  bridge = LQ1::Bridge.new(binary, trace)
  swift = Liquid::Spec::AdapterRunner.new(name: 'Swift-Liquid SequenceDrop')
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
      policy.fetch('cases').each_with_index do |item, index|
        relative = item.fetch('sourceLocation').fetch('file')
        path = File.realpath(File.join(root, relative))
        raise 'Fixture escapes pinned suite' unless path.start_with?(root + File::SEPARATOR)
        content, nodes = files[path] ||= begin
          content = File.binread(path)
          raise 'Fixture hash changed' unless Digest::SHA256.hexdigest(content) == item.fetch('sourceDigest')
          document = Psych.parse(content).root
          raise 'Unexpected YAML root' unless document.is_a?(Psych::Nodes::Mapping)
          pairs = document.children.each_slice(2).to_a.select { |key, _| key.value == 'specs' }
          raise 'Unexpected specs node' unless pairs.size == 1 && pairs[0][1].is_a?(Psych::Nodes::Sequence)
          [content, pairs[0][1].children]
        end
        raise 'Conflicting fixture digest' unless Digest::SHA256.hexdigest(content) == item.fetch('sourceDigest')
        line = item.fetch('sourceLocation').fetch('line')
        candidates = nodes.select { |node| node.start_line == line - 1 }
        raise 'Fixture identity changed' unless candidates.size == 1
        node = candidates.fetch(0)
        fixture = YAML.safe_load(content.lines[node.start_line...node.end_line].join,
          permitted_classes: [], permitted_symbols: [], aliases: false).fetch(0)
        recorded = original.fetch(index).fetch('fixture')
        raise 'Fixture differs from retained case study' unless fixture.slice(*recorded.keys) == recorded
        raise 'Unexpected fixture fields' unless (fixture.keys - %w[name template environment expected features render_errors complexity hint url]).empty?
        environment = fixture.fetch('environment')
        raise 'Unexpected environment' unless environment.is_a?(Hash) && environment.size == 1
        raise 'Unexpected SequenceDrop fixture input' unless environment.values.fetch(0) == 'instantiate:SequenceDrop'
        raise 'Unexpected fixture contract' unless fixture.fetch('features') == ['drops'] && fixture.fetch('template').is_a?(String) &&
          fixture.fetch('expected').is_a?(String) && [nil, false].include?(fixture['render_errors']) && item.fetch('renderMode') == 'raise' &&
          %w[strict2 lax].include?(item.fetch('parserMode'))
        features = item.fetch('featureTags').reject { |tag| tag.end_with?('_parsing') }.map(&:to_sym)
        spec = Liquid::Spec::LazySpec.new(name: item.fetch('name'), template: fixture.fetch('template'), expected: fixture.fetch('expected'),
          error_mode: item.fetch('parserMode').to_sym, features: features, raw_environment: environment, raw_filesystem: nil,
          source_file: path, line_number: line)
        bridge.case_key = item.fetch('caseID')
        swift_result = swift.run_single(spec)
        reference_result = reference.run_single(spec)
        rows << item.merge('expected' => fixture.fetch('expected'),
          'swift' => {passed: swift_result.passed?, status: swift_result.status, output: swift_result.output},
          'reference' => {passed: reference_result.passed?, status: reference_result.status, output: reference_result.output})
      end
    end
  ensure
    bridge.shutdown
  end
end
matched = rows.count { |row| row['swift'][:passed] && row['reference'][:passed] }
passed = rows.size == 5 && matched == 5
report = {status: passed ? 'passed' : 'failed', scope: 'five fixed pinned SequenceDrop cases; upstream comparator; no fixture expression evaluation',
  specPin: policy.fetch('specPin'), referencePin: policy.fetch('referencePin'), rubyVersion: RUBY_DESCRIPTION,
  liquidVersion: Liquid::VERSION, suiteVersion: Liquid::Spec::VERSION, dynamicEvaluationGuard: 'enabled',
  selectedCases: rows.size, matchedCases: matched, cases: rows}
File.write(output, JSON.pretty_generate(report) + "\n")
puts JSON.pretty_generate(report)
exit(passed ? 0 : 1)
