# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
require 'json'
require 'digest'

module LQ1
  # Narrow, source-bound exceptions to adapter exclusions, not test verdicts.
  module Admission
    RESOURCE_FEATURES = %i[shopify_resource_limits range_resource_limits].freeze
    def self.load(path)
      data = JSON.parse(File.read(path))
      groups = {'filesystemCandidates' => :unused_filesystem_callback,
                'rangeMetadataCandidates' => :unused_resource_limits}
      entries = {}
      groups.each do |group, kind|
        data.fetch(group).each do |item|
          id = item.fetch('caseID')
          raise "Duplicate admission candidate: #{id}" if entries.key?(id)
          entries[id] = [kind, item.fetch('sourceDigest')]
        end
      end
      raise 'Unexpected admission candidate population' unless entries.size == 58
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
      else
        raise 'Unknown admission kind'
      end
      kind
    end
  end
end
