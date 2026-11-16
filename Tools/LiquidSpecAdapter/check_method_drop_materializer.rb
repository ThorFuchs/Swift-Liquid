#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
require 'tmpdir'
require_relative 'method_drop_materializer'

checks = 0
assert = ->(condition) { raise 'Materializer regression' unless condition; checks += 1 }
reject = lambda do |&block|
  begin
    block.call
  rescue ArgumentError
    checks += 1
    next
  end
  raise 'Unsafe fixture or out-of-range input was accepted'
end
fixtures = {
  'drop_method_square_random' => {'name' => 'drop_method_square_random', 'template' => '{{ drop.square_#{n} }}',
    'expected' => '#{n * n}', 'generate' => {'n' => {'type' => 'numeric', 'min' => 1, 'max' => 100}},
    'environment' => {'drop' => 'instantiate:MethodDrop'}, 'features' => ['drops', 'randomness'], 'complexity' => 220, 'hint' => 'data'},
  'drop_method_echo_random' => {'name' => 'drop_method_echo_random', 'template' => '{{ drop.echo_#{n} }}',
    'expected' => '#{n}', 'generate' => {'n' => {'type' => 'numeric', 'min' => 1, 'max' => 1000}},
    'environment' => {'drop' => 'instantiate:MethodDrop'}, 'features' => ['drops', 'randomness'], 'complexity' => 220, 'hint' => 'data'}
}
square, echo = fixtures.values
assert.call(LQ1::MethodDropMaterializer.materialize(square, 1) == {template: '{{ drop.square_1 }}', expected: '1'})
assert.call(LQ1::MethodDropMaterializer.materialize(square, 100) == {template: '{{ drop.square_100 }}', expected: '10000'})
assert.call(LQ1::MethodDropMaterializer.materialize(echo, 1000) == {template: '{{ drop.echo_1000 }}', expected: '1000'})
[0, 101, -1, 1.0, '1', nil].each { |value| reject.call { LQ1::MethodDropMaterializer.materialize(square, value) } }
reject.call { LQ1::MethodDropMaterializer.materialize(echo, 1001) }
%w[template expected generate environment features complexity name].each do |field|
  changed = Marshal.load(Marshal.dump(square))
  changed[field] = nil
  reject.call { LQ1::MethodDropMaterializer.materialize(changed, 1) }
end
changed = square.merge('extra' => 'unexpected')
reject.call { LQ1::MethodDropMaterializer.materialize(changed, 1) }
['min', 'max'].each do |key|
  changed = Marshal.load(Marshal.dump(square))
  changed['generate']['n'][key] = changed['generate']['n'][key].to_f
  reject.call { LQ1::MethodDropMaterializer.materialize(changed, 1) }
end
changed = square.merge('complexity' => 220.0)
reject.call { LQ1::MethodDropMaterializer.materialize(changed, 1) }
Dir.mktmpdir('liquid-method-drop-inert-') do |directory|
  marker = File.join(directory, 'must-not-exist')
  changed = square.merge('expected' => '#{File.write(' + marker.inspect + ', "bad")}')
  reject.call { LQ1::MethodDropMaterializer.materialize(changed, 1) }
  assert.call(!File.exist?(marker))
end
puts "materializer checks passed: #{checks}; fixture expressions were never evaluated"
