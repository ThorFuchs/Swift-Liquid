# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
require 'json'
require 'digest'

module LQ1
  # Narrow, source-bound exceptions to adapter exclusions, not test verdicts.
  module Admission
    RESOURCE_FEATURES = %i[shopify_resource_limits range_resource_limits].freeze
    COMMENT_TEMPLATE = "{% liquid\necho \"A\"\ncomment\n  echo \"should not render\"\n  this is a comment\nendcomment\necho \"B\"\n%}".freeze
    def self.waived_features(kind)
      case kind
      when :unused_resource_limits then RESOURCE_FEATURES
      when :materialized_long_string then [:ruby_drops]
      when :missing_file_diagnostics then [:shopify_error_format]
      else []
      end
    end
    def self.load(path)
      data = JSON.parse(File.read(path))
      groups = {'filesystemCandidates' => :unused_filesystem_callback,
                'rangeMetadataCandidates' => :unused_resource_limits,
                'commentCandidates' => :comment_only_filesystem_callback,
                'longStringCandidates' => :materialized_long_string,
                'missingFileCandidates' => :missing_file_diagnostics}
      entries = {}
      groups.each do |group, kind|
        data.fetch(group).each do |item|
          id = item.fetch('caseID')
          raise "Duplicate admission candidate: #{id}" if entries.key?(id)
          entries[id] = [kind, item.fetch('sourceDigest')]
        end
      end
      raise 'Unexpected admission candidate population' unless entries.size == 63
      entries
    end

    def self.check(entry, spec, digest, missing)
      return nil unless entry
      kind, expected_digest = entry
      raise 'Admission fixture bytes changed' unless digest == expected_digest
      raise 'Admission cannot bypass a template factory or resource limit' if spec.raw_template_factory || !spec.raw_resource_limits.empty?
      case kind
      when :unused_filesystem_callback
        fs = spec.raw_filesystem
        raise 'Filesystem admission prerequisites changed' unless missing.empty? && fs.is_a?(Hash) && fs.key?('_error-message')
        sources = [spec.template] + fs.reject { |key, _| key == '_error-message' }.values
        raise 'Filesystem callback may be used' unless sources.all? { |source| source.is_a?(String) && !source.match?(/\b(?:include|render)\b/i) }
      when :unused_resource_limits
        raise 'Resource admission prerequisites changed' unless missing.sort == RESOURCE_FEATURES.sort
      when :comment_only_filesystem_callback
        raise 'Comment-only admission prerequisites changed' unless missing.empty? && spec.template == COMMENT_TEMPLATE && spec.raw_filesystem == {'_error-message' => 'This liquid context does not allow includes.'}
      when :materialized_long_string
        expected = {'long_string' => {'instantiate:LongString' => {'length' => 100_000}}}
        raise 'Long-string admission prerequisites changed' unless missing == [:ruby_drops] && spec.raw_environment == expected && spec.instantiate_environment == {'long_string' => 'X' * 100_000}
      when :missing_file_diagnostics
        fs = spec.raw_filesystem
        raise 'Missing-file diagnostic admission prerequisites changed' unless missing == [:shopify_error_format] && spec.raw_environment == {} && spec.render_errors && spec.errors.keys.map(&:to_s) == ['output'] && fs.is_a?(Hash) && !fs.key?('_error-message') && fs.all? { |k, v| k.is_a?(String) && v.is_a?(String) }
      else
        raise 'Unknown admission kind'
      end
      kind
    end
  end
end
