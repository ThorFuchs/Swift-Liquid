#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
ENV['BUNDLE_GEMFILE'] = File.expand_path('Gemfile', __dir__)
require 'bundler/setup'
require 'optparse'
require 'json'
require 'digest'
require 'base64'
require 'set'
require 'date'
require 'time'
require 'fileutils'
options = { suites: %w[basics liquid_ruby liquid_ruby_lax parser_errors partials], seed: 15401 }
OptionParser.new do |p|
  p.on('--binary PATH') { |v| options[:binary] = v }
  p.on('--output PATH') { |v| options[:output] = v }
  p.on('--suites LIST') { |v| options[:suites] = v.split(',') }
end.parse!
require 'liquid'
require 'active_support/all'
require 'liquid/spec'
require 'liquid/spec/deps/liquid_ruby'
require 'liquid/spec/cli/runner'
require_relative 'adapter'
raise 'Wrong Ruby Liquid version' unless Liquid::VERSION == '5.14.0'
raise 'Wrong liquid-spec version' unless Liquid::Spec::VERSION == '2.0.0'
output = File.expand_path(options.fetch(:output)); FileUtils.mkdir_p(output)
LiquidSpec.configure do |config|
  config.error_modes = LQ1::PARSER_MODES
  config.render_error_modes = LQ1::RENDER_MODES
  config.missing_features = LQ1::MISSING_FEATURES.keys
end

# Strict transport admission, before JSON generation or DropProxy coercion.
def transport_reason(value, ancestors = Set.new, depth = 0)
  return 'unsupported: JSON context exceeds adapter depth 64' if depth > 64
  case value
  when NilClass, TrueClass, FalseClass then nil
  when Integer then 'unsupported-by-domain: integer outside signed 64-bit Int' unless (-(2**63)...2**63).cover?(value)
  when Float then 'unsupported-by-domain: nonfinite float' unless value.finite?
  when String then 'transport-inapplicable: non-UTF8/binary string' unless value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?)
  when Array, Hash
    return 'transport-inapplicable: cyclic JSON value' if ancestors.include?(value.object_id)
    path = ancestors.dup.add(value.object_id)
    items = value.is_a?(Hash) ? value.to_a.flatten(1) : value
    return 'transport-inapplicable: non-string object key' if value.is_a?(Hash) && value.keys.any? { |key| !key.is_a?(String) }
    items.each do |child|
      reason = transport_reason(child, path, depth + 1)
      return reason if reason
    end
    nil
  else "transport-inapplicable: Ruby #{value.class} has no JSON value equivalent"
  end
end

# Evidence encoding only: never turn binary values into an engine context.
def receipt_value(value)
  case value
  when String
    return value if value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?)
    { receiptEncoding: value.encoding.name, byteLength: value.bytesize,
      bytesBase64: Base64.strict_encode64(value), sha256: Digest::SHA256.hexdigest(value) }
  when Array then value.map { |item| receipt_value(item) }
  when Hash then value.transform_values { |item| receipt_value(item) }
  else value
  end
end

def expected_category(spec)
  return 'parse-error' if spec.expects_parse_error?
  return 'render-error' if spec.expects_render_error?
  return 'recovered-error-or-output-pattern' if spec.expects_output_patterns?
  'output'
end

trace = File.open(File.join(output, 'RPC_TRACES.jsonl'), 'w')
bridge = LQ1::Bridge.new(options.fetch(:binary), trace)
adapter = Liquid::Spec::AdapterRunner.new(name: 'Swift-Liquid public API JSON-RPC')
adapter.set_missing_features(LQ1::MISSING_FEATURES.keys)
adapter.on_setup { |_ctx| }
adapter.on_compile { |ctx, source, parse_options| ctx[:template_id] = bridge.compile(source, parse_options) }
adapter.on_render { |ctx, assigns, render_options| bridge.render(ctx.fetch(:template_id), assigns, render_options) }
adapter.ensure_setup!
reference = Liquid::Spec::AdapterRunner.new(name: 'Pinned Ruby Liquid')
reference.on_setup { |_ctx| }
reference_observation = {}
reference.on_compile do |ctx, source, parse_options|
  reference_observation[:category] = 'compile'
  begin
    ctx[:template] = Liquid::Template.parse(source, **parse_options)
  rescue StandardError => error
    reference_observation[:category] = error.is_a?(Liquid::SyntaxError) ? 'parse-error' : 'operational-error'
    reference_observation[:error] = { type: error.class.name, message: error.message }
    raise
  end
end
reference.on_render do |ctx, assigns, render_options|
  context = Liquid::Context.build(static_environments: assigns,
    registers: Liquid::Registers.new(render_options.fetch(:registers)), rethrow_errors: render_options.fetch(:strict_errors))
  begin
    rendered = ctx.fetch(:template).render(context)
    reference_observation[:category] = ctx.fetch(:template).errors.empty? ? 'successful-render' : 'recovered-error'
    reference_observation[:errors] = ctx.fetch(:template).errors.map { |error| { type: error.class.name, message: error.message, line: error.line_number } }
    rendered
  rescue StandardError => error
    reference_observation[:category] = error.is_a?(Liquid::Error) ? 'render-error' : 'operational-error'
    reference_observation[:error] = { type: error.class.name, message: error.message }
    raise
  end
end
reference.ensure_setup!
rows = []; runs = []
Liquid::Spec::TimeFreezer.freeze_spec_time do
  options[:suites].each do |suite|
    specs = Liquid::Spec::SpecLoader.load_all(suite: suite.to_sym, random_seed: options[:seed])
    variants = specs.flat_map do |spec|
      expanded = Liquid::Spec::CLI::Runner.send(:expand_error_mode_variants, [spec])
      expanded.empty? ? [spec] : expanded # Preserve unsupported :warn records in the matrix.
    end
    start = rows.size
    variants.each_with_index do |spec, index|
      bridge.reset_observation
      relative = spec.source_file.sub(%r{\A.*?/specs/}, 'specs/')
      key = "#{suite}/#{relative}:#{spec.line_number}/#{spec.name}/#{spec.error_mode}/#{spec.render_errors ? 'inline' : 'raise'}"
      bridge.case_key = key
      row = { caseID: key, suite: suite, case: spec.name, parserMode: spec.error_mode, renderMode: spec.render_errors ? 'inline' : 'raise',
        featureTags: spec.features.map(&:to_s).sort, selected: false, reason: nil, adapterTransport: 'JSON-RPC 2.0 / protocol 1.0 / primitive JSON only',
        expectedCategory: expected_category(spec), observedCategory: nil, sourceLocation: { file: relative, line: spec.line_number },
        expectation: { output: spec.expected, outputPattern: spec.expected_pattern, errors: spec.errors },
        complexity: spec.complexity, sourceDigest: Digest::SHA256.file(spec.source_file).hexdigest, resultDigest: nil }
      missing = spec.features & LQ1::MISSING_FEATURES.keys
      reason = missing.empty? ? nil : missing.map { |feature| "#{feature}: #{LQ1::MISSING_FEATURES.fetch(feature)}" }.join('; ')
      reason ||= 'unsupported: declared parser mode is outside lax/strict/strict2' unless LQ1::PARSER_MODES.include?(spec.error_mode)
      unless reason
        begin
          reason = transport_reason(spec.instantiate_environment)
          reason ||= 'transport-inapplicable: custom filesystem error callback' if spec.raw_filesystem.is_a?(Hash) && spec.raw_filesystem.key?('_error-message')
          reason ||= 'transport-inapplicable: template factory callback' if spec.raw_template_factory
          reason ||= 'unsupported: Ruby resource-score policy has no verified Swift mapping' unless spec.raw_resource_limits.empty?
        rescue StandardError => e
          reason = "operational-error: fixture instantiation failed: #{e.class}: #{e.message}"
        end
      end
      if reason
        row[:reason] = reason
        row[:observedCategory] = if reason.include?('transport-inapplicable:') then 'transport-inapplicable' elsif reason.include?('unsupported-by-domain:') then 'unsupported-by-domain' elsif reason.include?('operational-error:') then 'operational-error' else 'unsupported' end
        row[:comparison] = 'not-executed'
        row[:disabled] = true
      else
        row[:selected] = true; row[:disabled] = false; row[:reason] = 'portable primitive JSON; declared parser/render modes; explicit partial map'
        result = adapter.run_single(spec)
        row[:observedCategory] = bridge.observed || 'operational-error'
        row[:resultDigest] = bridge.result_digest
        row[:comparison] = result.passed? ? 'matched' : 'mismatched'
        row[:actual] = result.output
        row[:expected] = result.expected
        row[:reportedErrors] = bridge.detail
        if %w[operational-error protocol-error domain-divergence compile].include?(row[:observedCategory])
          row[:comparison] = row[:observedCategory] == 'domain-divergence' ? 'domain-divergence' : 'operational-error'
        elsif %w[parse-error render-error].include?(row[:expectedCategory]) && row[:expectedCategory] != row[:observedCategory]
          row[:comparison] = 'mismatched'
        end
        # Independent pinned-Ruby result, with the same upstream comparator and clock.
        reference_observation.clear
        ref = reference.run_single(spec)
        row[:referenceObservedCategory] = reference_observation[:category]
        row[:referenceReportedErrors] = reference_observation[:error] || reference_observation[:errors]
        reference_phase_matches = !%w[parse-error render-error].include?(row[:expectedCategory]) || row[:expectedCategory] == reference_observation[:category]
        row[:referenceComparison] = ref.passed? && reference_phase_matches ? 'matched' : 'mismatched'
        row[:referenceActual] = ref.output unless row[:referenceComparison] == 'matched' && row[:comparison] == 'matched'
        if row[:comparison] != 'matched'
          row[:failureCategory] = row[:referenceComparison] == 'matched' ? 'unresolved' : 'test-suite-concern'
        end
      end
      row = receipt_value(row)
      row[:resultDigest] ||= Digest::SHA256.hexdigest(JSON.generate(row.reject { |k, _| k == :resultDigest }))
      rows << row
      File.write(File.join(output, 'ELIGIBILITY_MATRIX.json'), JSON.pretty_generate(rows) + "\n") if index % 500 == 0
    end
    selected = rows[start..]
    failures = selected.select { |r| r[:selected] && r[:comparison] != 'matched' }
    first = failures.map { |r| r[:complexity] }.min
    summary = { suite: suite, loadedSourceCases: specs.size, expandedVariants: variants.size,
      selected: selected.count { |r| r[:selected] }, comparisons: selected.map { |r| r[:comparison] }.tally,
      observedCategories: selected.map { |r| r[:observedCategory] }.tally,
      lowestFailingEligibleComplexity: first, eligibleCasesClearBelow: first,
      lowestUnqualifiedSourceComplexity: selected.select { |r| r[:disabled] || r[:comparison] != 'matched' }.map { |r| r[:complexity] }.min,
      complexityScope: 'eligible variants only; disabled cases prevent full-source clearance; no full language claim',
      disabledCases: selected.count { |r| r[:disabled] },
      skipped: selected.count { |r| r[:observedCategory] == 'skipped' }, fullLanguageClaim: false,
      timingCollection: false, seed: options[:seed] }
    runs << summary
    warn JSON.generate(summary)
  end
end
shutdown_error = nil
begin
  bridge.shutdown
rescue StandardError => error
  shutdown_error = "#{error.class}: #{error.message}"
  warn shutdown_error
ensure
  trace.close
end
File.write(File.join(output, 'ELIGIBILITY_MATRIX.json'), JSON.pretty_generate(rows) + "\n")
report = { schemaVersion: 1, suiteVersion: Liquid::Spec::VERSION, rubyVersion: RUBY_DESCRIPTION, liquidVersion: Liquid::VERSION,
  missingFeatures: LQ1::MISSING_FEATURES, parserModes: LQ1::PARSER_MODES, renderModes: LQ1::RENDER_MODES, runnerAPI: 'Liquid::Spec::AdapterRunner#run_single / CLI::Runner.expand_error_mode_variants',
  shutdownError: shutdown_error, suites: runs, gems: Gem.loaded_specs.transform_values { |s| s.version.to_s }, observedRows: rows.size }
File.write(File.join(output, 'SPEC_RUNS.json'), JSON.pretty_generate(report) + "\n")
puts JSON.generate(report.reject { |k, _| k == :missingFeatures })
# A mismatch is a nonzero command result, even though the evidence packet was produced.
exit(shutdown_error || rows.any? { |r| r[:selected] && r[:comparison] != 'matched' } ? 1 : 0)
