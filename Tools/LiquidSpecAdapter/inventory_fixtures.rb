#!/usr/bin/env ruby
# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
# Inert inventory only. This does not select cases or run the suite comparator.
require 'yaml'
require 'date'
require 'time'
require 'json'
require 'digest'
require 'open3'
require 'pathname'
require_relative 'method_drop_materializer'

module LQ1FixtureInventory
  PIN = '84bf25e0edbca5f7e530574788b0f875ab331f50'
  SUITES = %w[basics liquid_ruby liquid_ruby_lax parser_errors partials].freeze
  SUPPORTED = %w[strict2 strict lax].freeze
  PARSE_TAGS = %w[strict2_parsing strict_parsing lax_parsing].freeze
  MAX_BYTES = 16 * 1024 * 1024
  MAX_NODES = 1_000_000
  MAX_DEPTH = 128
  FILE_KEYS = %w[_metadata specs].freeze
  METADATA_KEYS = %w[hint doc required_options render_errors minimum_complexity complexity features data_files sequential_complexity].freeze
  SPEC_KEYS = %w[name template expected expected_pattern environment filesystem complexity hint doc error_mode render_errors features errors template_name resource_limits generate url caller_location message issue exception_renderer template_factory context_klass].freeze

  module NoDynamicEvaluation
    def eval(*)
      raise SecurityError, 'Dynamic Ruby evaluation is forbidden during fixture inventory'
    end
  end

  def self.install_eval_guard!
    Binding.prepend(NoDynamicEvaluation)
    Kernel.prepend(NoDynamicEvaluation)
    Kernel.singleton_class.prepend(NoDynamicEvaluation)
  end

  def self.require_check(condition, message)
    raise ArgumentError, message unless condition
  end

  def self.git(root, *args)
    out, err, status = Open3.capture3({'GIT_OPTIONAL_LOCKS' => '0', 'GIT_NO_LAZY_FETCH' => '1', 'GIT_NO_REPLACE_OBJECTS' => '1'},
      'git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-C', root, *args)
    raise "git failed: #{err}" unless status.success?
    out.strip
  end

  # Psych is restricted to these built-in value types; arbitrary YAML object
  # classes are never permitted. No fixture marker is dispatched to a registry.
  def self.load_data(bytes)
    require_check(bytes.bytesize <= MAX_BYTES, 'Fixture file exceeds byte limit')
    YAML.safe_load(bytes, permitted_classes: [Symbol, Date, Time, Range, Regexp], permitted_symbols: [], aliases: true)
  end

  def self.tracked_blobs(root, suite)
    entries = git(root.to_s, 'ls-tree', '-r', 'HEAD', '--', "specs/#{suite}").lines
    entries.each_with_object({}) do |line, result|
      metadata, path = line.strip.split("\t", 2)
      mode, type, oid = metadata.split(' ')
      require_check(path && mode == '100644' && type == 'blob' && oid&.match?(/\A[0-9a-f]{40}\z/), 'Unsupported pinned tree entry')
      result[path] = oid
    end
  end

  def self.verify_blob(bytes, relative, blobs)
    actual = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes)
    require_check(blobs[relative] == actual, 'Fixture bytes differ from pinned Git tree: ' + relative)
  end

  def self.walk(value, stats, depth = 0, seen = {})
    raise 'Fixture value nesting exceeds limit' if depth > MAX_DEPTH
    stats[:nodes] += 1
    raise 'Fixture node count exceeds limit' if stats[:nodes] > MAX_NODES
    if value.is_a?(Array) || value.is_a?(Hash)
      return if seen[value.object_id]
      seen[value.object_id] = true
    end
    case value
    when Hash
      value.each do |key, item|
        if key.is_a?(String) && key.start_with?('instantiate:')
          stats[:constructors] << key
        end
        stats[:non_string_keys] += 1 unless key.is_a?(String)
        walk(key, stats, depth + 1, seen)
        walk(item, stats, depth + 1, seen)
      end
    when Array
      value.each { |item| walk(item, stats, depth + 1, seen) }
    when String
      stats[:constructors] << value if value.start_with?('instantiate:')
      stats[:binary_strings] += 1 unless value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?)
    when NilClass, TrueClass, FalseClass, Integer, Float
      # These types require no callbacks or construction during inventory.
    when Date, Time, Range, Regexp, Symbol
      stats[:ruby_value_types] << value.class.name
    else
      raise "Unsupported YAML value class: #{value.class}"
    end
  end

  def self.stats(value)
    result = {nodes: 0, constructors: [], non_string_keys: 0, binary_strings: 0, ruby_value_types: []}
    walk(value, result)
    result[:constructors].uniq!
    result[:ruby_value_types].uniq!
    result
  end

  def self.wire_digest(value)
    encoded = JSON.generate(value)
    {jsonBytes: encoded.bytesize, sha256: Digest::SHA256.hexdigest(encoded)}
  end

  def self.materialized_evidence(item, selection, defaults)
    raise 'Generated fixture cannot be materialized before explicit policy' if item.key?('generate')
    environment = LQ1::SafeFixtureValues.materialize_environment(item['environment'] || {},
      allow_long: selection[:admission] == 'materialized_long_string')
    filesystem = item['filesystem'] || {}
    require_check(filesystem.instance_of?(Hash), 'Unsupported selected filesystem')
    source_files = filesystem.reject { |key, _| key == '_error-message' || key.to_s == 'instantiate' }
    require_check(source_files.all? { |key, value| key.instance_of?(String) && value.instance_of?(String) }, 'Non-string selected filesystem')
    normalized = source_files.transform_keys do |key|
      name = key.downcase
      name.end_with?('.liquid') ? name : "#{name}.liquid"
    end
    require_check(item['template'].instance_of?(String), 'Selected template is not text')
    {template: wire_digest(item['template']), environment: wire_digest(environment),
     filesystem: wire_digest(normalized),
     expectation: {output: item.key?('expected') ? item['expected'] : defaults['expected'],
                   outputPattern: item['expected_pattern'], errors: item['errors'] || {}}}
  end

  def self.lines(document)
    root = document&.root
    nodes = case root
    when Psych::Nodes::Sequence then root.children
    when Psych::Nodes::Mapping
      pairs = root.children.each_slice(2).select { |key, _| key.is_a?(Psych::Nodes::Scalar) && key.value == 'specs' }
      require_check(pairs.size == 1 && pairs[0][1].is_a?(Psych::Nodes::Sequence), 'Expected one specs sequence')
      pairs[0][1].children
    else raise 'Unexpected fixture document root'
    end
    nodes.map { |node| node.start_line + 1 }
  end

  def self.expand_modes(mode, features)
    declared = Array(mode).map(&:to_s)
    declared = %w[lax strict strict2 warn].select { |entry| features.include?("#{entry}_parsing") } if declared.empty?
    modes = if declared.empty?
      ['strict2']
    else
      [(%w[strict2 strict].find { |entry| declared.include?(entry) }), ('lax' if declared.include?('lax'))].compact
    end
    # The historical driver deliberately retains unsupported warn variants.
    modes = [Array(mode).first&.to_s] if modes.empty?
    require_check(modes.none?(&:nil?), 'Unsupported empty parser mode')
    modes.map { |entry| [entry, declared.size > 1] }
  end

  def self.run(spec_root, output)
    root = Pathname(spec_root).realpath
    require_check(git(root.to_s, 'rev-parse', 'HEAD') == PIN && git(root.to_s, 'status', '--porcelain').empty?, 'Reference checkout is not clean and pinned')
    $LOAD_PATH.unshift(root.join('lib').to_s)
    require_relative 'adapter'
    require_relative 'safe_fixture_selection'
    install_eval_guard!
    entries = LQ1::Admission.load(File.join(__dir__, 'ExclusionCandidates.json'))
    seen_admissions = []
    destination = Pathname(output).expand_path
    require_check(!destination.exist?, 'Refusing to overwrite inventory')
    inventory = []
    files = []
    SUITES.each do |suite|
      base = root.join('specs', suite)
      suite_file = base.join('suite.yml')
      blobs = tracked_blobs(root, suite)
      suite_bytes = suite_file.binread
      verify_blob(suite_bytes, "specs/#{suite}/suite.yml", blobs)
      suite_data = load_data(suite_bytes)
      require_check(suite_data.is_a?(Hash), 'Invalid suite configuration')
      suite_features = Array(suite_data['features']).map(&:to_s)
      defaults = suite_data.fetch('defaults', {})
      suite_paths = Dir.glob(base.join('*.yml').to_s).sort.reject { |path| File.basename(path) == 'suite.yml' }
      tracked = git(root.to_s, 'ls-files', '--', "specs/#{suite}/*.yml").lines.map(&:strip).sort
      discovered = (suite_paths + [suite_file.to_s]).map { |path| Pathname(path).relative_path_from(root).to_s }.sort
      require_check(discovered == tracked, 'Fixture file population differs from tracked pin')
      nested = Dir.glob(base.join('*', 'template.liquid').to_s)
      require_check(nested.empty?, 'Directory fixtures require explicit review')
      suite_paths.each do |path_string|
        path = Pathname(path_string).realpath
        require_check(path.to_s.start_with?(base.realpath.to_s + '/'), 'Fixture escapes suite root')
        bytes = path.binread
        verify_blob(bytes, path.relative_path_from(root).to_s, blobs)
        data = load_data(bytes)
        parsed = Psych.parse(bytes)
        location = lines(parsed)
        list, metadata = if data.is_a?(Hash)
          require_check((data.keys - FILE_KEYS).empty?, 'Unknown fixture file keys')
          [data.fetch('specs'), data.fetch('_metadata', {})]
        elsif data.is_a?(Array)
          [data, {}]
        else raise 'Unexpected fixture root'
        end
        require_check(list.is_a?(Array) && metadata.is_a?(Hash) && list.size == location.size, 'Fixture structure or source locations differ')
        require_check((metadata.keys - METADATA_KEYS).empty?, 'Unknown fixture metadata keys')
        require_check(!metadata['data_files'] || metadata['data_files'].empty?, 'Shared data files require explicit review')
        relative = path.relative_path_from(root).to_s
        digest = Digest::SHA256.hexdigest(bytes)
        files << {path: relative, sha256: digest, bytes: bytes.bytesize, sourceCases: list.size,
                  dataFiles: metadata['data_files'], suiteConfigSHA256: Digest::SHA256.hexdigest(suite_bytes)}
        features = (suite_features + Array(metadata['features'])).map(&:to_s).uniq
        source_options = metadata.fetch('required_options', {})
        list.each_with_index do |item, index|
          require_check(item.is_a?(Hash) && item['name'].is_a?(String), 'Missing fixture identity')
          require_check((item.keys - SPEC_KEYS).empty?, 'Unknown fixture keys')
          # Validate the two declared generator shapes as inert data; discovery
          # does not draw random numbers or interpolate either expression.
          LQ1::MethodDropMaterializer.bounds(item) if item.key?('generate')
          declared = item.key?('error_mode') ? item['error_mode'] : (source_options['error_mode'] || source_options[:error_mode] || defaults['error_mode'])
          inline = item.key?('render_errors') ? item['render_errors'] : (metadata.key?('render_errors') ? metadata['render_errors'] : defaults['render_errors'])
          # Match the pinned loader's source feature mutation and mixed String/Symbol
          # deduplication without evaluating a generator or invoking it.
          features += [:randomness] if item['generate'].is_a?(Hash) && !features.include?(:randomness)
          combined = (features + Array(item['features'])).uniq.map(&:to_s)
          primary = Array(declared).first&.to_s
          parse_tag = "#{primary}_parsing" if SUPPORTED.include?(primary)
          combined << parse_tag if parse_tag && !combined.include?(parse_tag)
          combined << 'inline_errors' if inline && !combined.include?('inline_errors')
          expanded = expand_modes(declared, combined)
          expanded.each do |mode, label|
            name = label ? "#{item['name']} [error_mode=#{mode}]" : item['name']
            # Unsupported warn is retained as the original unexpanded spec.
            tags = if mode == 'warn' && !SUPPORTED.include?(mode)
              combined
            else
              combined.reject { |tag| PARSE_TAGS.include?(tag) } + ["#{mode}_parsing"]
            end
            env = stats(item.fetch('environment', {}))
            fs = stats(item.fetch('filesystem', {}))
            case_id = "#{suite}/#{relative}:#{location[index]}/#{name}/#{mode}/#{inline ? 'inline' : 'raise'}"
            selection = LQ1::SafeFixtureSelection.decide(case_id: case_id, digest: digest, tags: tags, mode: mode,
              template: item['template'], environment: item['environment'] || {}, filesystem: item['filesystem'] || {},
              factory: item['template_factory'], limits: item['resource_limits'], inline: inline, errors: item['errors'], entries: entries)
            seen_admissions << case_id if selection[:admission]
            materialized = selection[:selected] ? materialized_evidence(item, selection, defaults) : nil
            inventory << {caseID: case_id,
              sourceLocation: {file: relative, line: location[index]}, sourceDigest: digest,
              parserMode: mode, renderMode: inline ? 'inline' : 'raise', featureTags: tags.sort,
              selection: selection, materialized: materialized,
              generated: item.key?('generate'), generatorData: item['generate'],
              environment: env, filesystem: fs,
              filesystemHasErrorCallback: item['filesystem'].is_a?(Hash) && item['filesystem'].key?('_error-message'),
              templateFactory: item.key?('template_factory'), resourceLimits: item.key?('resource_limits'),
              sourceHasDataFiles: !!metadata['data_files']}
          end
        end
      end
    end
    require_check(inventory.map { |row| row[:caseID] }.uniq.size == inventory.size, 'Duplicate expanded identity')
    require_check(seen_admissions.sort == entries.keys.sort, 'Admission candidate membership differs')
    result = {schemaVersion: 1, status: 'INERT_INVENTORY_NOT_QUALIFICATION', specPin: PIN, seed: nil,
              method: 'Psych safe_load with built-in value classes, inert eligibility preflight and bounded selected-case primitive materialization; no fixture interpolation, generator, registry constructor, factory or comparator is invoked.',
              limits: {fileBytes: MAX_BYTES, nodesPerField: MAX_NODES, depth: MAX_DEPTH}, files: files, variants: inventory}
    destination.dirname.mkpath
    File.write(destination, JSON.pretty_generate(result) + "\n", mode: 'wx')
    puts JSON.generate(files: files.size, sourceCases: files.sum { |file| file[:sourceCases] }, variants: inventory.size,
      selected: inventory.count { |row| row[:selection][:selected] }, generated: inventory.count { |row| row[:generated] }, templateFactories: inventory.count { |row| row[:templateFactory] },
      resourceLimits: inventory.count { |row| row[:resourceLimits] }, output: destination.to_s,
      sha256: Digest::SHA256.file(destination).hexdigest)
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'Usage: ruby inventory_fixtures.rb SPEC_ROOT NEW_OUTPUT' unless ARGV.size == 2
  LQ1FixtureInventory.run(*ARGV)
end
