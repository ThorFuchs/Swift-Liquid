# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Narrow, qualification-only primitive transport preflight and materializer.
# It never calls the upstream class registry or fixture-provided callbacks.
require 'date'
require 'time'
module LQ1
  module SafeFixtureValues
    MAX_DEPTH = 64
    MAX_NODES = 100_000
    LONG_LENGTH = 100_000
    LONG_ENVIRONMENT = {'long_string' => {'instantiate:LongString' => {'length' => LONG_LENGTH}}}.freeze
    # These pinned, untagged Ruby security fixtures are excluded as objects.
    # This mapping describes their transport boundary; no class is resolved.
    EXCLUDED_OBJECTS = %w[SecurityVictimDrop SecurityNestedDrop WideOpenObject
      UnsafeHashLikeObject ToLiquidHashObject ToLiquidStringObject ToLiquidArrayObject
      ToLiquidNilObject FakeDropObject SecurityEnumerableDrop].freeze

    def self.inspect_environment(value, allow_long: false)
      raise ArgumentError, 'Environment must be a plain mapping' unless value.instance_of?(Hash)
      if allow_long
        raise ArgumentError, 'LongString fixture shape changed' unless value == LONG_ENVIRONMENT &&
          value['long_string']['instantiate:LongString']['length'].instance_of?(Integer)
        return nil
      end
      state = {nodes: 0}
      reason(value, {}, 0, state)
    end

    def self.reason(value, ancestors, depth, state)
      return 'unsupported: JSON context exceeds adapter depth 64' if depth > MAX_DEPTH
      state[:nodes] += 1
      raise ArgumentError, 'Fixture value admission exceeds node limit' if state[:nodes] > MAX_NODES
      case value
      when NilClass, TrueClass, FalseClass
        nil
      when Integer
        'unsupported-by-domain: integer outside signed 64-bit Int' unless (-(2**63)...2**63).cover?(value)
      when Float
        'unsupported-by-domain: nonfinite float' unless value.finite?
      when String
        raise ArgumentError, 'Non-plain string input' unless value.instance_of?(String)
        if value.start_with?('instantiate:')
          marker = value.delete_prefix('instantiate:')
          raise ArgumentError, "Unrecognized fixture constructor: #{marker}" unless EXCLUDED_OBJECTS.include?(marker)
          return "transport-inapplicable: Ruby #{marker} has no JSON value equivalent"
        end
        'transport-inapplicable: non-UTF8/binary string' unless value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?)
      when Array, Hash
        raise ArgumentError, 'Non-plain fixture container' unless value.instance_of?(Array) || value.instance_of?(Hash)
        return 'transport-inapplicable: cyclic JSON value' if ancestors.key?(value.object_id)
        if value.is_a?(Hash)
          return 'transport-inapplicable: non-string object key' if value.keys.any? { |key| !key.instance_of?(String) }
          if value.size == 1 && value.keys.first.start_with?('instantiate:')
            marker = value.keys.first.delete_prefix('instantiate:').delete_suffix(':')
            raise ArgumentError, "Unrecognized fixture constructor: #{marker}" unless EXCLUDED_OBJECTS.include?(marker)
            return "transport-inapplicable: Ruby #{marker} has no JSON value equivalent"
          end
        end
        next_ancestors = ancestors.merge(value.object_id => true)
        entries = value.is_a?(Hash) ? value.to_a.flatten(1) : value
        entries.each do |entry|
          error = reason(entry, next_ancestors, depth + 1, state)
          return error if error
        end
        nil
      when Date, Time, Symbol
        "transport-inapplicable: Ruby #{value.class} has no JSON value equivalent"
      else
        raise ArgumentError, "Unknown fixture value type: #{value.class}"
      end
    end
    private_class_method :reason

    def self.materialize_environment(value, allow_long: false)
      rejection = inspect_environment(value, allow_long: allow_long)
      raise ArgumentError, rejection if rejection
      return {'long_string' => 'X' * LONG_LENGTH} if allow_long
      copy(value)
    end

    def self.copy(value)
      case value
      when Hash then value.each_with_object({}) { |(key, child), output| output[key.dup] = copy(child) }
      when Array then value.map { |child| copy(child) }
      when String then value.dup
      else value
      end
    end
    private_class_method :copy
  end
end
