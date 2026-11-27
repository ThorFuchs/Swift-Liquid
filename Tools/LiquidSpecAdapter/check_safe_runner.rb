#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
ENV['BUNDLE_GEMFILE'] = File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'set'
require 'liquid'
require 'active_support/all'
require 'tmpdir'
require 'open3'
require 'liquid/spec'
require 'liquid/spec/deps/liquid_ruby'
require_relative 'adapter'
require_relative 'inventory_fixtures'
require_relative 'safe_runner_spec'
require_relative 'safe_fixture_selection'

spec_root = ARGV.fetch(0) { abort 'Usage: check_safe_runner.rb SPEC_ROOT' }

runner = Liquid::Spec::AdapterRunner.new(name: 'Safe runner negative control')
runner.on_setup { |_ctx| }
runner.on_compile { |_ctx, _source, _options| raise LQ1::OperationalError, 'expected probe failure' }
runner.on_render { |_ctx, _environment, _options| raise 'Render must not run' }
runner.ensure_setup!
Liquid::Spec::ClassRegistry.singleton_class.prepend(LQ1::ForbidFixtureRegistry)
LQ1FixtureInventory.install_eval_guard!
[-> { binding.eval('nil') }, -> { Kernel.eval('nil') }, -> { eval('nil') },
 -> { Liquid::Spec::ClassRegistry.instantiate('LongString', {'length' => 1}) }].each do |probe|
  begin
    probe.call
    raise 'A forbidden execution guard did not engage'
  rescue SecurityError
    # Constant guard probes do not evaluate fixture content or instantiate it.
  end
end

spec = LQ1::SafeRunnerSpec.new(name: 'operational', template: '{{ x }}', error_mode: :strict2,
  errors: {'render_error' => ['expected probe failure']}, prepared_environment: {'x' => 'value'}, raw_filesystem: {})
raw = runner.run_single(spec)
raise 'Negative control did not exercise the upstream comparator' unless raw.passed?
raise 'Operational error was counted as a language match' unless LQ1::SafeRunnerVerdict.classify(
  raw_passed: raw.passed?, expected: 'render-error', observed: 'operational-error') == 'operational-error'
raise 'Unobserved preparation failure was counted as a match' unless LQ1::SafeRunnerVerdict.classify(
  raw_passed: true, expected: 'render-error', observed: nil) == 'operational-error'

begin
  LQ1::SafeFixtureValues.materialize_environment({'x' => {'_instantiate' => 'MethodDrop'}})
  raise 'Wire constructor marker was not rejected'
rescue ArgumentError
  # A fixture cannot smuggle a Drop constructor into the public adapter.
end

drop_policy = LQ1::SafeStandardDrops.load
candidate = drop_policy.values.find { |entry| entry.fetch('constructors').first.fetch('class') == 'BooleanDrop' }
item = candidate.fetch('fixture')
arguments = {case_id: candidate.fetch('caseID'), digest: candidate.fetch('sourceDigest'), tags: candidate.fetch('featureTags'),
  mode: candidate.fetch('parserMode'), template: item.fetch('template'), environment: item.fetch('environment'),
  filesystem: item.fetch('filesystem', {}), factory: nil, limits: {}, inline: false, errors: item.fetch('errors', {}),
  entries: {}, drop_candidates: drop_policy, item: item}
raise 'Guarded fixture was not selected' unless LQ1::SafeFixtureSelection.decide(**arguments)[:admission] == 'guarded_standard_drop'
held = LQ1::SafeFixtureSelection.decide(**arguments.merge(case_id: 'unapproved-identity', factory: -> { raise 'callback executed' }))
raise 'Unapproved identity was selected' if held[:selected]
[
  arguments.merge(digest: 'changed'),
  arguments.merge(tags: arguments[:tags] + ['ruby_drops']),
  arguments.merge(factory: -> { raise 'callback executed' }),
  arguments.merge(item: item.merge('environment' => {'x' => {'_instantiate' => 'MethodDrop', 'params' => {}}}))
].each do |changed|
  begin
    LQ1::SafeFixtureSelection.decide(**changed)
    raise 'Changed Drop contract was accepted'
  rescue ArgumentError
    # Selection fails before construction or fixture callbacks.
  end
end

# Exercise the same production inventory entry point against a modified pinned
# checkout. It must reject the changed fixture before interpreting its content.
Dir.mktmpdir('liquid-fixture-negative-') do |directory|
  checkout = File.join(directory, 'spec')
  [["git", "clone", "--shared", "--no-checkout", spec_root, checkout],
   ["git", "-C", checkout, "checkout", "--detach", LQ1FixtureInventory::PIN]].each do |command|
    _out, err, status = Open3.capture3(*command)
    raise "Fixture negative-control setup failed: #{err}" unless status.success?
  end
  $fixture_negative_executed = false
  File.open(File.join(checkout, 'specs/basics/drops.yml'), 'a') do |stream|
    stream.write('\n# #{($fixture_negative_executed = true)}\n')
  end
  begin
    LQ1FixtureInventory.run(checkout, File.join(directory, 'result.json'))
    raise 'Changed fixture was accepted'
  rescue ArgumentError => error
    raise unless error.message.include?('not clean and pinned')
  end
  raise 'Excluded fixture content was executed' if $fixture_negative_executed
  raise 'Changed fixture emitted an inventory' if File.exist?(File.join(directory, 'result.json'))
end
puts 'Integrated safe runner guards and operational-error control passed.'
