#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
require_relative 'inventory_fixtures'
require_relative 'safe_fixture_values'
require_relative 'safe_fixture_selection'

# Isolated selection controls use a minimal known policy. The full inventory
# separately loads the real adapter policy from the pinned checkout.
module LQ1
  MISSING_FEATURES = {drops: 'blocked', ruby_drops: 'blocked'}.freeze
  PARSER_MODES = %i[strict2 strict lax].freeze
end

module SafeFixturePreparationChecks
  def self.check(condition, message)
    raise message unless condition
  end

  def self.rejects(message)
    begin
      yield
    rescue ArgumentError, Psych::DisallowedClass
      return
    end
    raise "Expected rejection: #{message}"
  end

  def self.run
    LQ1FixtureInventory.install_eval_guard!
    [-> { binding.eval('nil') }, -> { Kernel.eval('nil') }, -> { eval('nil') }].each do |probe|
      begin
        probe.call
        raise 'Evaluation guard did not engage'
      rescue SecurityError
        # The probe contains only a constant and is intercepted before execution.
      end
    end
    $fixture_expression_executed = false
    raw = 'template: "#{($fixture_expression_executed = true)}"'
    data = LQ1FixtureInventory.load_data(raw)
    check(data['template'].include?('fixture_expression_executed') && !$fixture_expression_executed, 'Fixture expression was executed')
    rejects('arbitrary YAML object class') { LQ1FixtureInventory.load_data('--- !ruby/object:Object {}') }
    rejects('oversized fixture') { LQ1FixtureInventory.load_data(' ' * (LQ1FixtureInventory::MAX_BYTES + 1)) }

    sample = {'x' => [1, 'text', nil, true]}
    copy = LQ1::SafeFixtureValues.materialize_environment(sample)
    check(copy == sample && !copy.equal?(sample) && !copy['x'].equal?(sample['x']), 'Primitive copy changed')
    check(LQ1::SafeFixtureValues.inspect_environment({'drop' => 'instantiate:SecurityVictimDrop'}) ==
      'transport-inapplicable: Ruby SecurityVictimDrop has no JSON value equivalent', 'Excluded object is not held')
    rejects('unknown constructor') { LQ1::SafeFixtureValues.materialize_environment({'x' => 'instantiate:NotARegisteredFixture'}) }
    long = {'long_string' => {'instantiate:LongString' => {'length' => 100_000}}}
    result = LQ1::SafeFixtureValues.materialize_environment(long, allow_long: true)
    check(result['long_string'].bytesize == 100_000 && result['long_string'].count('X') == 100_000, 'LongString materialization changed')
    rejects('changed constructor parameter') { LQ1::SafeFixtureValues.materialize_environment({'long_string' => {'instantiate:LongString' => {'length' => 100_001}}}, allow_long: true) }
    rejects('unapproved constructor') { LQ1::SafeFixtureValues.materialize_environment(long) }
    callback_called = false
    callback = -> { callback_called = true }
    held = LQ1::SafeFixtureSelection.decide(case_id: 'held', digest: 'digest', tags: ['drops'], mode: 'strict2',
      template: '', environment: {'x' => callback}, filesystem: {}, factory: callback, limits: {}, inline: false, errors: {}, entries: {})
    check(!held[:selected] && !callback_called, 'Excluded fixture invoked a callback')
    candidate = {'long' => [:materialized_long_string, 'digest']}
    rejected = {'long_string' => {'instantiate:LongString' => {'length' => 100_001}}}
    rejects('changed constructor cannot bypass selection') do
      LQ1::SafeFixtureSelection.decide(case_id: 'long', digest: 'digest', tags: ['ruby_drops'], mode: 'strict2',
        template: '', environment: rejected, filesystem: {}, factory: nil, limits: {}, inline: false, errors: {}, entries: candidate)
    end
    cycle = []; cycle << cycle
    check(LQ1::SafeFixtureValues.inspect_environment({'x' => cycle}) == 'transport-inapplicable: cyclic JSON value', 'Cycle not rejected')
    rejects('node budget') { LQ1::SafeFixtureValues.materialize_environment({'x' => Array.new(100_001, nil)}) }
    check(LQ1::SafeFixtureValues.inspect_environment({'x' => (2**63)}) == 'unsupported-by-domain: integer outside signed 64-bit Int', 'Integer domain not enforced')

    square = {'name' => 'drop_method_square_random', 'template' => '{{ drop.square_#{n} }}', 'expected' => '#{n * n}',
      'environment' => {'drop' => 'instantiate:MethodDrop'}, 'features' => ['drops', 'randomness'],
      'complexity' => 220, 'hint' => 'data', 'generate' => {'n' => {'type' => 'numeric', 'min' => 1, 'max' => 100}}}
    check(LQ1::MethodDropMaterializer.bounds(square) == (1..100), 'Known generated shape rejected')
    rejects('unknown generator') { LQ1::MethodDropMaterializer.bounds(square.merge('name' => 'unknown')) }
    rejects('changed generator') { LQ1::MethodDropMaterializer.bounds(square.merge('expected' => '#{system("false")}')) }
    rejects('generator bounds') { LQ1::MethodDropMaterializer.materialize(square, 101) }
    check(!$fixture_expression_executed, 'Fixture expression was executed')
    puts 'Safe fixture preparation negative controls passed (isolated modules; full runner not yet integrated).'
  end
end

SafeFixturePreparationChecks.run if $PROGRAM_NAME == __FILE__
