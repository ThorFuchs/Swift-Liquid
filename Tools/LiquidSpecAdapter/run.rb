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
  p.on('--spec-path PATH') { |v| options[:spec_path] = v }
  p.on('--suites LIST') { |v| options[:suites] = v.split(',') }
end.parse!
require 'liquid'
require 'active_support/all'
require 'liquid/spec'
require 'liquid/spec/deps/liquid_ruby'
require_relative 'adapter'
require_relative 'admission'
require_relative 'inventory_fixtures'
require_relative 'safe_runner_spec'
raise 'Wrong Ruby Liquid version' unless Liquid::VERSION == '5.14.0'
raise 'Wrong liquid-spec version' unless Liquid::Spec::VERSION == '2.0.0'
raise 'Only the pinned complete suite selection is supported' unless options[:suites] == LQ1FixtureInventory::SUITES && options[:seed] == 15401
raise 'A pinned spec checkout is required' unless options[:spec_path]
output = File.expand_path(options.fetch(:output)); FileUtils.mkdir_p(output)
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
    reference_observation[:error] = { type: error.class.name, message: error.message, line: error.respond_to?(:line_number) ? error.line_number : nil, column: error.respond_to?(:column) ? error.column : nil }
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
    reference_observation[:error] = { type: error.class.name, message: error.message, line: error.respond_to?(:line_number) ? error.line_number : nil, column: error.respond_to?(:column) ? error.column : nil }
    raise
  end
end
reference.ensure_setup!
Liquid::Spec::ClassRegistry.singleton_class.prepend(LQ1::ForbidFixtureRegistry)
rows = []; runs = []
admission = LQ1::Admission.load(File.join(__dir__, 'ExclusionCandidates.json'))
seen_admissions = Set.new
LQ1FixtureInventory.run(options.fetch(:spec_path), File.join(output, 'PREPARATION_INVENTORY.json')) do |jobs, inventory|
Liquid::Spec::TimeFreezer.freeze_spec_time do
  options[:suites].each do |suite|
    variants = jobs.select { |job| job[:suite] == suite }
    start = rows.size
    variants.each_with_index do |job, index|
      bridge.reset_observation
      prepared = job[:row]
      item = job[:item]
      selection = prepared[:selection]
      relative = prepared[:sourceLocation][:file]
      key = prepared[:caseID]
      environment = if selection[:selected]
        LQ1::SafeFixtureValues.materialize_environment(item['environment'] || {}, allow_long: selection[:admission] == 'materialized_long_string')
      else
        {}
      end
      complexity = item['complexity'] || job[:suiteData]['minimum_complexity'] || job[:metadata]['minimum_complexity'] || job[:metadata]['complexity'] || 1000
      spec = LQ1::SafeRunnerSpec.new(name: job[:name], template: item['template'], template_name: item['template_name'],
        expected: item.key?('expected') ? item['expected'] : job[:defaults]['expected'], expected_pattern: item['expected_pattern'],
        errors: item['errors'] || {}, complexity: complexity, error_mode: job[:mode].to_sym, render_errors: job[:inline],
        features: job[:tags], source_file: job[:path], line_number: prepared[:sourceLocation][:line],
        prepared_environment: environment, raw_filesystem: selection[:selected] ? (item['filesystem'] || {}) : {}, raw_resource_limits: {})
      bridge.case_key = key
      row = { caseID: key, suite: suite, case: spec.name, parserMode: spec.error_mode, renderMode: spec.render_errors ? 'inline' : 'raise',
        featureTags: spec.features.map(&:to_s).sort, selected: false, reason: nil, adapterTransport: 'JSON-RPC 2.0 / protocol 1.0 / primitive JSON only',
        expectedCategory: expected_category(spec), observedCategory: nil, sourceLocation: { file: relative, line: spec.line_number },
        expectation: { output: spec.expected, outputPattern: spec.expected_pattern, errors: spec.errors },
        complexity: spec.complexity, sourceDigest: Digest::SHA256.file(spec.source_file).hexdigest, resultDigest: nil }
      admitted = selection[:admission]&.to_sym
      seen_admissions.add(key) if admitted
      reason = selection[:reason]
      row[:expectationMaterialization] = 'deferred-excluded-generator' if item.key?('generate')
      if reason
        row[:reason] = reason
        row[:observedCategory] = if reason.include?('transport-inapplicable:') then 'transport-inapplicable' elsif reason.include?('unsupported-by-domain:') then 'unsupported-by-domain' elsif reason.include?('operational-error:') then 'operational-error' else 'unsupported' end
        row[:comparison] = 'not-executed'
        row[:qualificationComparison] = 'not-executed'
        row[:disabled] = true
      else
        row[:selected] = true; row[:disabled] = false; row[:reason] = 'portable primitive JSON; declared parser/render modes; explicit partial map'
        row[:admission] = admitted.to_s if admitted
        adapter.set_missing_features(LQ1::MISSING_FEATURES.keys - LQ1::Admission.waived_features(admitted))
        begin
          result = adapter.run_single(spec)
        ensure
          adapter.set_missing_features(LQ1::MISSING_FEATURES.keys)
        end
        row[:observedCategory] = bridge.observed || 'operational-error'
        row[:resultDigest] = bridge.result_digest
        verdict = receipt_value({ status: result.status, passed: result.passed?, output: result.output, expected: result.expected })
        verdict[:sha256] = Digest::SHA256.hexdigest(JSON.generate(verdict))
        row[:upstreamVerdict] = verdict
        row[:comparison] = result.passed? ? 'matched' : 'mismatched'
        row[:qualificationComparison] = row[:comparison]
        row[:compileOutcome] = bridge.compile_outcome
        row[:renderedOutput] = bridge.last_result && bridge.last_result['output']
        row[:semanticResultDigest] = Digest::SHA256.hexdigest(JSON.generate(bridge.last_result))
        row[:diagnosticEvidence] = {
          messagePatternsMatch: spec.errors.empty? ? nil : adapter.send(:matches_error_patterns?, spec, result.output.to_s),
          locationMatch: spec.errors.empty? ? nil : (spec.expects_output_patterns? ? adapter.send(:matches_output_location?, spec, result.output.to_s) : adapter.send(:matches_error_location?, spec, bridge.exception))
        }
        row[:actual] = result.output
        row[:expected] = result.expected
        row[:reportedErrors] = bridge.detail
        row[:qualificationComparison] = LQ1::SafeRunnerVerdict.classify(raw_passed: result.passed?, expected: row[:expectedCategory], observed: row[:observedCategory])
        # Independent pinned-Ruby result, with the same upstream comparator and clock.
        reference_observation.clear
        ref = reference.run_single(spec)
        row[:referenceObservedCategory] = reference_observation[:category]
        row[:referenceReportedErrors] = reference_observation[:error] || reference_observation[:errors]
        row[:referenceUpstreamVerdict] = receipt_value({ status: ref.status, passed: ref.passed?, output: ref.output, expected: ref.expected })
        row[:referenceUpstreamVerdict][:sha256] = Digest::SHA256.hexdigest(JSON.generate(row[:referenceUpstreamVerdict]))
        row[:referenceComparison] = ref.passed? ? 'matched' : 'mismatched'
        row[:referenceQualificationComparison] = LQ1::SafeRunnerVerdict.classify(raw_passed: ref.passed?, expected: row[:expectedCategory], observed: reference_observation[:category])
        row[:referenceActual] = ref.output unless row[:referenceQualificationComparison] == 'matched' && row[:qualificationComparison] == 'matched'
        if row[:qualificationComparison] != 'matched'
          row[:failureCategory] = row[:referenceQualificationComparison] == 'matched' ? 'unresolved' : 'test-suite-concern'
        end
      end
      row = receipt_value(row)
      row[:resultDigest] ||= Digest::SHA256.hexdigest(JSON.generate(row.reject { |k, _| k == :resultDigest }))
      rows << row
      File.write(File.join(output, 'ELIGIBILITY_MATRIX.json'), JSON.pretty_generate(rows) + "\n") if index % 500 == 0
    end
    selected = rows[start..]
    failures = selected.select { |r| r[:selected] && r[:qualificationComparison] != 'matched' }
    first = failures.map { |r| r[:complexity] }.min
    source_cases = inventory[:files].select { |file| file[:path].start_with?("specs/#{suite}/") }.sum { |file| file[:sourceCases] }
    summary = { suite: suite, loadedSourceCases: source_cases, expandedVariants: variants.size,
      selected: selected.count { |r| r[:selected] }, qualificationComparisons: selected.map { |r| r[:qualificationComparison] }.tally, comparisons: selected.map { |r| r[:comparison] }.tally,
      observedCategories: selected.map { |r| r[:observedCategory] }.tally,
      lowestFailingEligibleComplexity: first, eligibleCasesClearBelow: first,
      lowestUnqualifiedSourceComplexity: selected.select { |r| r[:disabled] || r[:qualificationComparison] != 'matched' }.map { |r| r[:complexity] }.min,
      complexityScope: 'eligible variants only; disabled cases prevent full-source clearance; no full language claim',
      disabledCases: selected.count { |r| r[:disabled] },
      skipped: selected.count { |r| r[:observedCategory] == 'skipped' }, fullLanguageClaim: false,
      timingCollection: false, seed: options[:seed] }
    runs << summary
    warn JSON.generate(summary)
  end
end
end
raise 'Admission candidate membership changed' unless seen_admissions == admission.keys.to_set
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
report = { schemaVersion: 2, comparatorPolicy: 'comparison/upstreamVerdict preserve original result.passed?; qualificationComparison additionally rejects operational and parse/render-phase failures; supplemental dimensions never create passes', suiteVersion: Liquid::Spec::VERSION, rubyVersion: RUBY_DESCRIPTION, liquidVersion: Liquid::VERSION,
  fixturePreparation: 'inert-selection-v1; excluded generators remain unevaluated',
  missingFeatures: LQ1::MISSING_FEATURES, featurePolicies: LQ1::FEATURE_POLICIES,
  numericDomainPolicy: 'Int64 plus finite binary Double; context is preflighted; source-literal/arithmetic mismatches require individual domain review', parserModes: LQ1::PARSER_MODES, renderModes: LQ1::RENDER_MODES, runnerAPI: 'Liquid::Spec::AdapterRunner#run_single / inert fixture preparation',
  shutdownError: shutdown_error, suites: runs, gems: Gem.loaded_specs.transform_values { |s| s.version.to_s }, observedRows: rows.size }
File.write(File.join(output, 'SPEC_RUNS.json'), JSON.pretty_generate(report) + "\n")
puts JSON.generate(report.reject { |k, _| k == :missingFeatures })
# A mismatch is a nonzero command result, even though the evidence packet was produced.
exit(shutdown_error || rows.any? { |r| r[:selected] && r[:qualificationComparison] != 'matched' } ? 1 : 0)
