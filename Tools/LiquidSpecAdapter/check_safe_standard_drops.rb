#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
ENV['BUNDLE_GEMFILE'] = File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'liquid'
require 'liquid/spec'
require 'liquid/spec/deps/standard_drops'
require_relative 'safe_standard_drops'

def rejects(label)
  begin
    yield
  rescue ArgumentError
    return
  end
  raise "Expected rejection: #{label}"
end

policy = LQ1::SafeStandardDrops.load
raise 'Wrong candidate count' unless policy.size == 56
policy.each_value do |candidate|
  item = candidate.fetch('fixture')
  args = {item: item, digest: candidate.fetch('sourceDigest'), tags: candidate.fetch('featureTags'),
          mode: candidate.fetch('parserMode'), inline: candidate.fetch('renderMode') == 'inline', factory: nil, limits: {}}
  LQ1::SafeStandardDrops.validate(candidate, **args)
  rejected = Marshal.load(Marshal.dump(item))
  rejected['environment'] = {'x' => {'_instantiate' => 'MethodDrop', 'params' => {}}}
  rejects('injected wire marker') { LQ1::SafeStandardDrops.validate(candidate, **args.merge(item: rejected)) }
  rejects('changed digest') { LQ1::SafeStandardDrops.validate(candidate, **args.merge(digest: 'changed')) }
  rejects('changed feature policy') { LQ1::SafeStandardDrops.validate(candidate, **args.merge(tags: args[:tags] + ['ruby_drops'])) }
  rejects('callback') { LQ1::SafeStandardDrops.validate(candidate, **args.merge(factory: -> { raise 'executed' })) }
  description = LQ1::SafeStandardDrops.description(item.fetch('environment'))
  raise 'Object construction failed' unless LQ1::SafeStandardDrops.construct(description).instance_of?(Hash)
end
rejects('unknown constructor') { LQ1::SafeStandardDrops.description({'x' => 'instantiate:Kernel'}) }
rejects('changed constructor parameter') { LQ1::SafeStandardDrops.description({'x' => {'instantiate:BooleanDrop' => {'value' => 1}}}) }
rejects('wire marker') { LQ1::SafeStandardDrops.description({'x' => {'_instantiate' => 'MethodDrop', 'params' => {}}}) }
rejects('wire marker at construction') { LQ1::SafeStandardDrops.construct({'x' => {'_instantiate' => 'MethodDrop', 'params' => {}}}) }
rejects('unapproved constructor argument') { LQ1::SafeStandardDrops.description({'x' => {'instantiate:MethodDrop' => {'extra' => 1}}}) }
rejects('node budget') { LQ1::SafeStandardDrops.description({'x' => Array.new(100_001)}) }
cycle = []; cycle << cycle
rejects('cyclic fixture') { LQ1::SafeStandardDrops.description({'x' => cycle}) }
$drop_fixture_executed = false
changed = Marshal.load(Marshal.dump(policy.values.first.fetch('fixture')))
changed['template'] = '#{($drop_fixture_executed = true)}'
candidate = policy.values.first
rejects('fixture expression') do
  LQ1::SafeStandardDrops.validate(candidate, item: changed, digest: candidate.fetch('sourceDigest'),
    tags: candidate.fetch('featureTags'), mode: candidate.fetch('parserMode'), inline: false, factory: nil, limits: {})
end
raise 'Fixture expression executed' if $drop_fixture_executed
puts '56 exact standard Drop descriptions and negative controls passed.'
