# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
gem 'date', '3.5.1'
gem 'time', '0.4.2'
require 'liquid'
require 'date'
require 'time'
require 'json'
require 'digest'
require 'open3'

root = File.expand_path('..', __dir__)
pins = JSON.parse(File.read(File.join(root, 'Documentation/ConformancePins.json')))
abort 'Reference Liquid version changed' unless Liquid::VERSION == pins['shopifyLiquid']['version']
abort 'Reference Date version changed' unless Date::VERSION == pins['rubyDate']['version']
abort 'Reference Time version changed' unless Time::VERSION == pins['rubyDate']['time']['version']
loaded = $LOADED_FEATURES.find { |path| path.end_with?('/lib/liquid.rb') }
abort 'Cannot locate reference source' unless loaded
reference_root = File.dirname(File.dirname(loaded))
commit, _, status = Open3.capture3('git', '-C', reference_root, 'rev-parse', 'HEAD')
abort 'Reference source must match the pinned commit' unless status.success? && commit.strip == pins['shopifyLiquid']['commit']
changes, _, clean_status = Open3.capture3('git', '-C', reference_root, 'status', '--porcelain')
abort 'Reference checkout must be clean' unless clean_status.success? && changes.empty?
ENV['TZ'] = 'UTC'

def read_pin(root, pin)
  path = File.join(root, pin['path'])
  abort "Pinned hash changed: #{pin['path']}" unless Digest::SHA256.file(path).hexdigest == pin['sha256']
  JSON.parse(File.read(path))['tests']
end

golden = read_pin(root, pins['goldenLiquid'])
probes = read_pin(root, pins['authoredProbes'])
dates = read_pin(root, pins['dateFilters'])
grammar = read_pin(root, pins['rubyDate']['grammarCases'])
recoveries = read_pin(root, pins['recoveredErrors'])
[[golden, 1098], [probes, 221], [dates, 376], [grammar, 337]].each do |cases, count|
  abort 'Pinned case count changed' unless cases.length == count
end
memory_files = Struct.new(:templates) do
  def read_template_file(path)
    templates.fetch(path)
  end
end
original_now = Time.method(:now)
results = (golden + probes + dates).map do |test|
  if test['referenceTime']
    fixed = test['referenceTime']
    Time.define_singleton_method(:now) { Time.at(fixed).utc }
  else
    Time.define_singleton_method(:now, original_now)
  end
  environment = Liquid::Environment.build { |env| env.file_system = memory_files.new(test['templates'] || {}) }
  tags = test['tags'] || []
  mode = tags.include?('strict2') ? :strict2 : (tags.include?('strict') ? :strict : :lax)
  expected_diagnostics = recoveries[test['name']] || test['diagnostics'] || []
  begin
    template = Liquid::Template.parse(test['template'], environment: environment, error_mode: mode, line_numbers: true)
    output = test['invalid'] ? template.render!(test['data'] || {}) : template.render(test['data'] || {})
    matched = !test['invalid'] && (test.key?('result') ? output == test['result'] : test['results'].include?(output))
    diagnostics = template.errors.map do |error|
      diagnostic = { 'message' => error.to_s(false), 'line' => error.line_number }
      diagnostic['templateName'] = error.template_name if error.template_name
      diagnostic
    end
    if test['outsideYearDomain']
      # This is an evaluated policy boundary, never a conformant successful render.
      date = Liquid::Utils.to_date(test['data']['value'])
      bounded = date && !(1..9999).cover?(date.year)
      { name: test['name'], status: matched && bounded && diagnostics.empty? ? 'outside-domain' : 'failed', output: output, referenceYear: date&.year }
    elsif diagnostics.any?
      qualified = matched && diagnostics == expected_diagnostics
      { name: test['name'], status: qualified ? 'recovered-error' : 'reference-error', output: output, outputMatched: matched,
        diagnostics: diagnostics, errors: template.errors.map { |error| { errorClass: error.class.name, message: error.message } } }
    else
      { name: test['name'], status: matched && expected_diagnostics.empty? ? 'rendered' : 'failed', output: output }
    end
  rescue Liquid::Error => error
    { name: test['name'], status: test['invalid'] ? 'expected-error' : 'reference-error',
      errorClass: error.class.name, message: error.message }
  rescue StandardError => error
    # Foreign exceptions and infrastructure failures cannot qualify Liquid errors.
    { name: test['name'], status: 'reference-error', errorClass: error.class.name, message: error.message }
  end
end
Time.define_singleton_method(:now, original_now)
grammar.each do |test|
  begin
    parsed = Date._parse(test['input'], test['completeYear'])
    fields = parsed.select { |key, _| [:year, :mon, :mday, :yday, :hour, :min, :sec, :zone].include?(key) }.transform_keys(&:to_s)
    if fraction = parsed[:sec_fraction]
      precision = 0
      precision += 1 until (fraction * 10**precision).denominator == 1
      fields['fraction'] = (fraction * 10**precision).to_i.to_s.rjust(precision, '0').sub(/0+\z/, '')
    end
    results << { name: test['name'], status: fields == test['fields'] ? 'parsed' : 'failed', fields: fields }
  rescue StandardError => error
    results << { name: test['name'], status: 'reference-error', errorClass: error.class.name, message: error.message }
  end
end
counts = results.group_by { |result| result[:status] }.transform_values(&:length)
qualified = %w[rendered parsed expected-error recovered-error outside-domain].sum { |kind| counts[kind] || 0 }
receipt = {
  ruby: RUBY_DESCRIPTION, liquidVersion: Liquid::VERSION, dateVersion: Date::VERSION, timeVersion: Time::VERSION,
  referenceCommit: commit.strip, timezone: ENV['TZ'], lineNumbers: true,
  goldenCases: golden.length, compatibilityProbes: probes.length, dateFilterCases: dates.length, grammarCases: grammar.length,
  successfulRenders: counts['rendered'] || 0, parsedCases: counts['parsed'] || 0,
  expectedErrors: counts['expected-error'] || 0, recoveredErrors: counts['recovered-error'] || 0,
  outsideSupportedDomain: counts['outside-domain'] || 0, referenceErrors: counts['reference-error'] || 0,
  observed: results.length, passed: qualified, failed: results.length - qualified, skipped: 0,
  fixtureSHA256: pins['goldenLiquid']['sha256'], probeSHA256: pins['authoredProbes']['sha256'], cases: results
}
File.write(ARGV[0], JSON.pretty_generate(receipt) + "\n") if ARGV[0]
puts JSON.generate(receipt.reject { |key, _| key == :cases })
exit(receipt[:failed].zero? ? 0 : 1)
