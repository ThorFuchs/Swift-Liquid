# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Run with: ruby -I /path/to/pinned/Shopify-liquid/lib Scripts/check_reference.rb
require 'liquid'
require 'json'
require 'digest'
require 'rbconfig'
require 'open3'

root = File.expand_path('..', __dir__)
pins = JSON.parse(File.read(File.join(root, 'Documentation/ConformancePins.json')))
abort 'Reference must be Shopify Liquid 5.14.0' unless Liquid::VERSION == pins['shopifyLiquid']['version']
loaded = $LOADED_FEATURES.find { |path| path.end_with?('/lib/liquid.rb') }
abort 'Cannot locate reference source' unless loaded
reference_root = File.dirname(File.dirname(loaded))
commit, _, status = Open3.capture3('git', '-C', reference_root, 'rev-parse', 'HEAD')
abort 'Reference source must match the pinned commit' unless status.success? && commit.strip == pins['shopifyLiquid']['commit']
changes, _, clean_status = Open3.capture3('git', '-C', reference_root, 'status', '--porcelain')
abort 'Reference checkout must be clean' unless clean_status.success? && changes.empty?
fixture_path = File.join(root, pins['goldenLiquid']['path'])
abort 'Fixture hash changed' unless Digest::SHA256.file(fixture_path).hexdigest == pins['goldenLiquid']['sha256']
ENV['TZ'] = 'UTC'

memory_files = Struct.new(:templates) do
  def read_template_file(path)
    templates.fetch(path)
  end
end

tests = JSON.parse(File.read(fixture_path))['tests']
abort 'Fixture count changed' unless tests.length == 1098
probe_path = File.join(root, pins['authoredProbes']['path'])
abort 'Probe hash changed' unless Digest::SHA256.file(probe_path).hexdigest == pins['authoredProbes']['sha256']
probes = JSON.parse(File.read(probe_path))['tests']
abort 'Probe count changed' unless probes.length == 185
tests += probes
results = tests.map do |test|
  file_system = memory_files.new(test['templates'] || {})
  environment = Liquid::Environment.build { |env| env.file_system = file_system }
  tags = test['tags'] || []
  mode = tags.include?('strict2') ? :strict2 : (tags.include?('strict') ? :strict : :lax)
  begin
    template = Liquid::Template.parse(test['template'], environment: environment, error_mode: mode, line_numbers: true)
    output = test['invalid'] ? template.render!(test['data'] || {}) : template.render(test['data'] || {})
    matched = !test['invalid'] && (test.key?('result') ? output == test['result'] : test['results'].include?(output))
    if template.errors.any?
      { name: test['name'], status: 'reference-error', output: output, outputMatched: matched,
        errors: template.errors.map { |error| { errorClass: error.class.name, message: error.message } } }
    else
      { name: test['name'], status: matched ? 'rendered' : 'failed', output: output }
    end
  rescue Liquid::Error => error
    { name: test['name'], status: test['invalid'] ? 'expected-error' : 'reference-error',
      expectedError: test['invalid'] == true, errorClass: error.class.name, message: error.message }
  rescue StandardError => error
    # Missing partials, foreign runtime failures and infrastructure errors never
    # qualify an expected Liquid error or a successful render.
    { name: test['name'], status: 'reference-error', errorClass: error.class.name, message: error.message }
  end
end
rendered = results.count { |result| result[:status] == 'rendered' }
expected_errors = results.count { |result| result[:status] == 'expected-error' }
reference_errors = results.count { |result| result[:status] == 'reference-error' }
receipt = {
  ruby: RUBY_DESCRIPTION, liquidVersion: Liquid::VERSION, referenceCommit: commit.strip,
  timezone: ENV['TZ'], lineNumbers: true, goldenCases: 1098, compatibilityProbes: 185,
  fixtureSHA256: pins['goldenLiquid']['sha256'], probeSHA256: pins['authoredProbes']['sha256'], observed: results.length,
  successfulRenders: rendered, expectedErrors: expected_errors, referenceErrors: reference_errors,
  passed: rendered + expected_errors, failed: results.length - rendered - expected_errors, skipped: 0, cases: results
}
if ARGV[0]
  File.write(ARGV[0], JSON.pretty_generate(receipt) + "\n")
end
puts JSON.generate(receipt.reject { |key, _| key == :cases })
exit(receipt[:failed].zero? ? 0 : 1)
