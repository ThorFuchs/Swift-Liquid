# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
require 'json'
require 'set'
require_relative 'safe_fixture_values'

module LQ1
  # Qualification-only, closed descriptions of the pinned standard Drop cases.
  # Inspecting a description never constructs a Ruby object or executes fixture
  # code. Construction is permitted only after an exact case policy is selected.
  module SafeStandardDrops
    STUDY = File.expand_path('../../Documentation/LQ1/STANDARD-DROPS-2.1.json', __dir__)
    POLICY_NAMES = %w[BooleanDropCases NumberDropCases StringDropCases MethodDropCases
      IndexDropCases SequenceDropCases NestedDropCases NilDropCases OpaqueDropCases
      ErrorDropCases ErrorDropInlineCases].freeze
    SIMPLE = %w[MethodDrop IndexDrop SequenceDrop NilDrop OpaqueDrop ErrorDrop].freeze
    Descriptor = Struct.new(:kind, :parameters, keyword_init: true)
    private_constant :Descriptor

    def self.load
      study = JSON.parse(File.read(STUDY))
      raise ArgumentError, 'Unexpected study pin' unless study.fetch('liquidSpecCommit') == '84bf25e0edbca5f7e530574788b0f875ab331f50' &&
        study.fetch('rubyLiquidCommit') == '4e39ae4cc3da73921923c0669e0fc84a66b2f696'
      cases = study.fetch('cases').to_h { |item| [item.fetch('caseID'), item] }
      raise ArgumentError, 'Unexpected study identity population' unless cases.size == 56 && study.fetch('cases').size == 56
      policy_ids = []
      POLICY_NAMES.each do |name|
        policy = JSON.parse(File.read(File.join(__dir__, "#{name}.json")))
        raise ArgumentError, 'Policy pin changed' unless policy.fetch('specPin') == study.fetch('liquidSpecCommit') && policy.fetch('referencePin') == study.fetch('rubyLiquidCommit')
        (policy.fetch('cases') + policy.fetch('generatedCases', [])).each do |item|
          id = item['caseID'] || "basics/#{policy.fetch('fixture')}:#{item.fetch('line')}/#{item.fetch('name')}/strict2/raise"
          raise ArgumentError, 'Duplicate Drop policy identity' if policy_ids.include?(id)
          candidate = cases.fetch(id)
          if item.key?('caseID')
            %w[sourceLocation sourceDigest parserMode renderMode featureTags].each do |field|
              raise ArgumentError, 'Targeted Drop policy metadata changed' unless item.fetch(field) == candidate.fetch(field)
            end
          else
            raise ArgumentError, 'Compact Drop policy metadata changed' unless policy.fetch('fixtureSHA256') == candidate.fetch('sourceDigest') &&
              item.fetch('name') == candidate.fetch('fixture').fetch('name') && item.fetch('line') == candidate.fetch('sourceLocation').fetch('line')
          end
          policy_ids << id
        end
      end
      raise ArgumentError, 'Drop policy membership changed' unless policy_ids.to_set == cases.keys.to_set
      cases.freeze
    end

    def self.validate(candidate, item:, digest:, tags:, mode:, inline:, factory:, limits:)
      raise ArgumentError, 'Drop fixture identity or digest changed' unless digest == candidate.fetch('sourceDigest') &&
        mode == candidate.fetch('parserMode') && (inline ? 'inline' : 'raise') == candidate.fetch('renderMode') &&
        tags.sort == candidate.fetch('featureTags').sort
      raise ArgumentError, 'Drop fixture cannot waive factory or resource limits' if factory || !(limits || {}).empty?
      recorded = candidate.fetch('fixture')
      raise ArgumentError, 'Drop fixture description changed' unless recorded.all? { |key, value| item.key?(key) && item[key] == value }
      description(item.fetch('environment', {}))
      true
    end

    # Returns internal descriptors, never fixture-provided wire marker hashes.
    # The source case must be validated before calling this.
    def self.description(value, depth = 0, state = {nodes: 0}, ancestors = {})
      raise ArgumentError, 'Drop fixture nesting exceeds limit' if depth > SafeFixtureValues::MAX_DEPTH
      state[:nodes] += 1
      raise ArgumentError, 'Drop fixture exceeds node limit' if state[:nodes] > SafeFixtureValues::MAX_NODES
      case value
      when String
        if value.start_with?('instantiate:')
          marker(value.delete_prefix('instantiate:'), {})
        else
          raise ArgumentError, 'Invalid string' unless value.instance_of?(String) && value.valid_encoding? &&
            (value.encoding == Encoding::UTF_8 || value.ascii_only?)
          value.dup
        end
      when Array
        raise ArgumentError, 'Non-plain array' unless value.instance_of?(Array)
        raise ArgumentError, 'Cyclic Drop fixture' if ancestors.key?(value.object_id)
        next_ancestors = ancestors.merge(value.object_id => true)
        value.map { |element| description(element, depth + 1, state, next_ancestors) }
      when Hash
        raise ArgumentError, 'Non-plain mapping' unless value.instance_of?(Hash) && value.keys.all? { |key| key.instance_of?(String) }
        raise ArgumentError, 'Untrusted wire marker' if value.key?('_instantiate') || value.key?('_rpc_drop')
        raise ArgumentError, 'Cyclic Drop fixture' if ancestors.key?(value.object_id)
        next_ancestors = ancestors.merge(value.object_id => true)
        if value.size == 1 && value.keys.first.start_with?('instantiate:')
          marker(value.keys.first.delete_prefix('instantiate:').delete_suffix(':'), value.values.first)
        else
          raise ArgumentError, 'Malformed constructor mapping' if value.keys.any? { |key| key.start_with?('instantiate:') }
          value.to_h { |key, child| [key.dup, description(child, depth + 1, state, next_ancestors)] }
        end
      when Integer
        raise ArgumentError, 'Integer outside supported domain' unless (-(2**63)...2**63).cover?(value)
        value
      when NilClass, TrueClass, FalseClass
        value
      else
        raise ArgumentError, 'Unsupported Drop fixture value'
      end
    end

    def self.marker(kind, params)
      raise ArgumentError, 'Constructor parameters must be a plain mapping' unless params.instance_of?(Hash)
      normalized = case kind
      when *SIMPLE
        raise ArgumentError, 'Unexpected constructor parameters' unless params.empty?
        {}
      when 'BooleanDrop'
        raise ArgumentError, 'BooleanDrop parameter changed' unless params.keys == ['value'] && [true, false].include?(params['value'])
        {'value' => params['value']}
      when 'NumberDrop'
        number = params['value']
        raise ArgumentError, 'NumberDrop parameter changed' unless params.keys == ['value'] && number.instance_of?(Integer) && (-(2**63)...2**63).cover?(number)
        {'value' => number}
      when 'StringDrop'
        raise ArgumentError, 'StringDrop parameter changed' unless params.empty? || (params.keys == ['value'] && params['value'].instance_of?(String))
        {'value' => params['value']}
      when 'NestedDrop'
        raise ArgumentError, 'NestedDrop parameter changed' unless params.empty? || params == {'value' => 3}
        {'value' => 3}
      else
        raise ArgumentError, 'Unknown standard Drop constructor'
      end
      Descriptor.new(kind: kind.freeze, parameters: normalized.freeze).freeze
    end

    # The case statement is the only class selection. No fixture string is
    # passed to a registry, constant lookup, send, eval, or dynamic dispatch.
    def self.construct(value)
      case value
      when Descriptor
        p = value.parameters
        case value.kind
        when 'BooleanDrop' then StandardBooleanDrop.new(p)
        when 'NumberDrop' then StandardNumberDrop.new(p)
        when 'StringDrop' then StandardStringDrop.new(p)
        when 'MethodDrop' then StandardMethodDrop.new(p)
        when 'IndexDrop' then StandardIndexDrop.new(p)
        when 'SequenceDrop' then StandardSequenceDrop.new(p)
        when 'NestedDrop' then StandardNestedDrop.new(p)
        when 'NilDrop' then StandardNilDrop.new(p)
        when 'OpaqueDrop' then StandardOpaqueDrop.new(p)
        when 'ErrorDrop' then StandardErrorDrop.new(p)
        else raise ArgumentError, 'Invalid internal standard Drop kind'
        end
      when Array then value.map { |item| construct(item) }
      when Hash
        raise ArgumentError, 'Untrusted wire marker' if value.key?('_instantiate') || value.key?('_rpc_drop')
        value.to_h { |key, child| [key, construct(child)] }
      else value
      end
    end

    def self.wire_evidence(value)
      case value
      when Descriptor then {'_instantiate' => value.kind, 'params' => value.parameters}
      when Array then value.map { |item| wire_evidence(item) }
      when Hash
        raise ArgumentError, 'Untrusted wire marker' if value.key?('_instantiate') || value.key?('_rpc_drop')
        value.to_h { |key, child| [key, wire_evidence(child)] }
      else value
      end
    end
  end
end
