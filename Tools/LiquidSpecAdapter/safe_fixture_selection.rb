# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Eligibility-only mirror of the historical selector. No upstream constructor,
# generator, filesystem callback, or comparator is invoked in this module.
require_relative 'admission'
require_relative 'safe_fixture_values'

module LQ1
  module SafeFixtureSelection
    SpecView = Struct.new(:template, :raw_environment, :raw_filesystem,
                          :raw_template_factory, :raw_resource_limits, :render_errors, :errors,
                          keyword_init: true)

    def self.admission(entry, spec, digest, missing)
      return nil unless entry
      kind, expected_digest = entry
      return Admission.check(entry, spec, digest, missing) unless kind == :materialized_long_string
      raise ArgumentError, 'Admission fixture bytes changed' unless digest == expected_digest
      raise ArgumentError, 'LongString admission cannot bypass factory or resource limits' if spec.raw_template_factory || !spec.raw_resource_limits.empty?
      raise ArgumentError, 'LongString feature policy changed' unless missing == [:ruby_drops]
      SafeFixtureValues.inspect_environment(spec.raw_environment, allow_long: true)
      kind
    end

    def self.decide(case_id:, digest:, tags:, mode:, template:, environment:, filesystem:, factory:, limits:, inline:, errors:, entries:)
      spec = SpecView.new(template: template, raw_environment: environment, raw_filesystem: filesystem,
                          raw_template_factory: factory, raw_resource_limits: limits || {},
                          render_errors: inline, errors: errors || {})
      missing = tags.map(&:to_sym) & LQ1::MISSING_FEATURES.keys
      admitted = admission(entries[case_id], spec, digest, missing)
      missing -= Admission.waived_features(admitted)
      rejection = missing.empty? ? nil : missing.map { |feature| "#{feature}: #{LQ1::MISSING_FEATURES.fetch(feature)}" }.join('; ')
      rejection ||= 'unsupported: declared parser mode is outside lax/strict/strict2' unless LQ1::PARSER_MODES.include?(mode.to_sym)
      unless rejection
        rejection = SafeFixtureValues.inspect_environment(environment, allow_long: admitted == :materialized_long_string)
        if !rejection && [:unused_filesystem_callback, :comment_only_filesystem_callback, :missing_file_diagnostics].include?(admitted)
          raise ArgumentError, 'Admitted filesystem must be a plain mapping' unless filesystem.instance_of?(Hash)
          rejection = SafeFixtureValues.inspect_environment(filesystem.reject { |key, _| key == '_error-message' })
        end
        rejection ||= 'transport-inapplicable: custom filesystem error callback' if ![:unused_filesystem_callback, :comment_only_filesystem_callback].include?(admitted) && filesystem.is_a?(Hash) && filesystem.key?('_error-message')
        rejection ||= 'transport-inapplicable: template factory callback' if factory
        rejection ||= 'unsupported: Ruby resource-score policy has no verified Swift mapping' unless spec.raw_resource_limits.empty?
      end
      raise ArgumentError, "Admission failed safe preflight: #{case_id}: #{rejection}" if admitted && rejection
      {selected: rejection.nil?, reason: rejection, admission: admitted&.to_s}
    end
  end
end
