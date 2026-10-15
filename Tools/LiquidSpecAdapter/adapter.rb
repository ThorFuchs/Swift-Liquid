# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0
require 'json'
require 'digest'
require 'liquid/spec/json_rpc/subprocess'

module LQ1
  # Deliberately no :core, parser-mode, inline-error or randomness exclusion.
  MISSING_FEATURES = {
    drops: 'transport-inapplicable: no typed host-object/callback API',
    ruby_drops: 'transport-inapplicable: Ruby-native runtime objects',
    drop_class_output: 'transport-inapplicable: Ruby class identity',
    binary_data: 'transport-inapplicable: non-UTF8 strings',
    template_factory: 'transport-inapplicable: host template factory callback',
    shopify_tags: 'unsupported: hosted Shopify tags are outside open-source core',
    shopify_filters: 'unsupported: hosted Shopify filters are outside open-source core',
    shopify_objects: 'unsupported: hosted Shopify objects are outside open-source core',
    shopify_error_handling: 'unsupported: hosted error policy',
    shopify_blank: 'unsupported: hosted blank policy',
    shopify_string_access: 'unsupported: hosted string-access policy',
    shopify_error_format: 'unsupported: hosted error formatting',
    shopify_includes: 'unsupported: hosted include policy',
    shopify_resource_limits: 'unsupported: Ruby score units are not Swift logical quotas',
    range_resource_limits: 'unsupported: no verified range-score mapping'
  }.freeze
  FEATURE_POLICIES = {
    ruby_types: 'per-case primitive JSON admission; Ruby classes, symbol keys, cycles and out-of-domain numbers are explicitly rejected'
  }.freeze
  PARSER_MODES = %i[strict2 strict lax].freeze
  RENDER_MODES = %i[raise inline].freeze

  class SyntaxError < StandardError
    attr_reader :line, :column
    def initialize(error)
      @line, @column = error.values_at('line', 'column')
      super("Liquid syntax error#{@line ? " (line #{@line})" : ''}: #{error.fetch('message')}")
    end
  end
  class RenderError < SyntaxError
    def initialize(error)
      super
      @render_message = "Liquid error#{line ? " (line #{line})" : ''}: #{error.fetch('message')}"
    end
    def message = @render_message
  end
  class OperationalError < StandardError; end
  class DomainError < StandardError; end

  class Process < Liquid::Spec::JsonRpc::Subprocess
    attr_accessor :case_key
    def initialize(command, trace)
      super(command, timeout: 10)
      @trace = trace
    end
    def shutdown
      return unless running?
      write_message(Liquid::Spec::JsonRpc::Protocol.notification(method: 'quit'))
      @stdin.close
      unless @wait_thr.join(10)
        super
        raise OperationalError, 'quit did not complete within 10 seconds'
      end
      status = @wait_thr.value
      @trace.puts(JSON.generate(direction: 'process-exit', exitCode: status.exitstatus, signal: status.termsig))
      cleanup
      raise OperationalError, 'Subprocess quit unsuccessfully' unless status.success?
    end
    def abort_failed_exchange
      @trace.puts(JSON.generate(case: @case_key, direction: 'process-abort', reason: 'failed protocol exchange; next compile starts a new process'))
      abort_timed_out_process
    end
    private
    def write_message(message)
      redacted = Marshal.load(Marshal.dump(message))
      params = redacted['params'] || {}
      %w[template environment filesystem].each do |key|
        next unless params.key?(key)
        bytes = JSON.generate(params[key])
        params[key] = { 'redacted' => true, 'jsonBytes' => bytes.bytesize, 'sha256' => Digest::SHA256.hexdigest(bytes) }
      end
      @trace.puts(JSON.generate(case: @case_key, direction: 'request', message: redacted))
      super(message)
    end
    def read_response_for(expected_id)
      line = @stdout.gets
      raise OperationalError, 'Subprocess closed stdout' unless line
      @trace.puts(JSON.generate(case: @case_key, direction: 'response', raw: line.chomp))
      message = Liquid::Spec::JsonRpc::Protocol.decode(line.chomp)
      raise OperationalError, 'Unexpected callback or response ID' if message.key?('method') || message['id'] != expected_id
      message
    end
  end

  class Bridge
    attr_reader :observed, :detail, :result_digest
    attr_accessor :case_key
    def initialize(command, trace)
      @command, @trace = command, trace
      @process = Process.new(command, trace)
      @process.initialize!
    end
    def reset_observation
      @observed, @detail, @result_digest = nil, nil, nil
    end
    def send_request(method, params)
      @process.case_key = @case_key
      begin
        response = @process.send_request(method, params)
      rescue Liquid::Spec::JsonRpc::SubprocessError, OperationalError, IOError => error
        @observed = 'operational-error'
        @detail = { 'type' => 'transport_failure', 'message' => "#{error.class}: #{error.message}" }
        @process.abort_failed_exchange
        raise OperationalError, @detail.fetch('message')
      end
      @result_digest = Digest::SHA256.hexdigest(JSON.generate(response))
      if response['error']
        @observed = 'protocol-error'; @detail = response['error']
        raise OperationalError, JSON.generate(@detail)
      end
      result = response.fetch('result')
      if result['error']
        @detail = result['error']
        @observed = { 'syntax_error' => 'parse-error', 'render_error' => 'render-error', 'domain_error' => 'domain-divergence' }.fetch(@detail['type'], 'operational-error')
        klass = { 'parse-error' => SyntaxError, 'render-error' => RenderError, 'domain-divergence' => DomainError }.fetch(@observed, OperationalError)
        raise klass, @detail.fetch('message') unless [SyntaxError, RenderError].include?(klass)
        raise klass.new(@detail)
      end
      result
    end
    def compile(source, options)
      @observed = 'compile'
      unless @process.running?
        @process = Process.new(@command, @trace)
        @process.case_key = @case_key
        @process.initialize!
      end
      files = options[:file_system]&.to_h || {}
      send_request('compile', 'template' => source, 'options' => { 'error_mode' => (options[:error_mode] || :strict2).to_s, 'line_numbers' => true }, 'filesystem' => files).fetch('template_id')
    end
    def render(id, environment, options)
      registers = { 'current_time' => options.fetch(:registers).fetch(:current_time).iso8601 }
      result = send_request('render', 'template_id' => id, 'environment' => environment,
        'options' => { 'strict_errors' => options.fetch(:strict_errors), 'registers' => registers })
      @detail = result.fetch('errors', [])
      @observed = @detail.empty? ? 'successful-render' : 'recovered-error'
      result.fetch('output')
    end
    def shutdown = @process.shutdown
  end
end
