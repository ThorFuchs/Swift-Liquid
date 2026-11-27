#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
ENV['BUNDLE_GEMFILE'] = File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'set'
require 'liquid'
require 'active_support/all'
require 'liquid/spec'
require 'liquid/spec/deps/liquid_ruby'
require_relative 'adapter'
require_relative 'inventory_fixtures'
require_relative 'safe_runner_spec'

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
puts 'Integrated safe runner guards and operational-error control passed.'
