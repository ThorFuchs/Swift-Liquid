# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
require_relative 'safe_fixture_values'
require_relative 'safe_standard_drops'

module LQ1
  # AdapterRunner's comparator is unchanged. This spec only exposes prepared
  # primitive data and refuses the upstream fixture class registry and factories.
  class SafeRunnerSpec < Liquid::Spec::LazySpec
    def initialize(prepared_environment:, prepared_drop: false, **arguments)
      @prepared_environment = prepared_environment
      @prepared_drop = prepared_drop
      super(**arguments.merge(raw_environment: prepared_environment, raw_template_factory: nil))
    end

    def instantiate_environment
      return SafeStandardDrops.construct(@prepared_environment) if @prepared_drop
      SafeFixtureValues.materialize_environment(@prepared_environment)
    end

    def instantiate_template_factory
      nil
    end

    def instantiate_filesystem
      raise ArgumentError, 'Filesystem must be a plain mapping' unless raw_filesystem.instance_of?(Hash)
      unless raw_filesystem.all? { |key, value| key.instance_of?(String) && value.instance_of?(String) }
        raise ArgumentError, 'Filesystem entries must be strings'
      end
      super
    end
  end

  module ForbidFixtureRegistry
    def instantiate(*)
      raise SecurityError, 'Fixture class registry is forbidden during full qualification'
    end
  end

  module SafeRunnerVerdict
    def self.classify(raw_passed:, expected:, observed:)
      return 'domain-divergence' if observed == 'domain-divergence'
      return 'operational-error' if %w[operational-error protocol-error compile].include?(observed) || observed.nil?
      return 'mismatched' if %w[parse-error render-error].include?(expected) && expected != observed
      raw_passed ? 'matched' : 'mismatched'
    end
  end
end
