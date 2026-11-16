# frozen_string_literal: true
# SPDX-License-Identifier: Apache-2.0

module LQ1
  # This is a closed mapping for two exact pinned fixture shapes, not a Ruby
  # expression interpreter. Fixture strings are compared as inert bytes only.
  module MethodDropMaterializer
    SHAPES = {
      'drop_method_square_random' => {
        template: '{{ drop.square_#{n} }}', expected: '#{n * n}', maximum: 100, operation: :square
      }.freeze,
      'drop_method_echo_random' => {
        template: '{{ drop.echo_#{n} }}', expected: '#{n}', maximum: 1000, operation: :echo
      }.freeze
    }.freeze
    ALLOWED_KEYS = %w[complexity environment expected features generate hint name template].freeze

    def self.bounds(fixture)
      raise ArgumentError, 'Fixture must be a plain mapping' unless fixture.instance_of?(Hash)
      shape = SHAPES[fixture['name']]
      raise ArgumentError, 'Unknown generated fixture' unless shape
      expected_generation = {'n' => {'type' => 'numeric', 'min' => 1, 'max' => shape.fetch(:maximum)}}
      generation = fixture['generate']
      numeric_bounds = generation.instance_of?(Hash) && generation['n'].instance_of?(Hash) &&
        generation['n']['min'].instance_of?(Integer) && generation['n']['max'].instance_of?(Integer)
      unless fixture.keys.sort == ALLOWED_KEYS && fixture['template'] == shape.fetch(:template) &&
             fixture['expected'] == shape.fetch(:expected) && numeric_bounds && generation == expected_generation &&
             fixture['environment'] == {'drop' => 'instantiate:MethodDrop'} &&
             fixture['features'] == ['drops', 'randomness'] && fixture['complexity'].instance_of?(Integer) &&
             fixture['complexity'] == 220 && fixture['hint'].is_a?(String)
        raise ArgumentError, 'Generated fixture shape changed'
      end
      1..shape.fetch(:maximum)
    end

    def self.materialize(fixture, number)
      range = bounds(fixture)
      raise ArgumentError, 'Generated input outside declared integer range' unless number.instance_of?(Integer) && range.cover?(number)
      # These operations are explicitly authored here; no fixture text is executed.
      if SHAPES.fetch(fixture.fetch('name')).fetch(:operation) == :square
        {template: "{{ drop.square_#{number} }}", expected: (number * number).to_s}
      else
        {template: "{{ drop.echo_#{number} }}", expected: number.to_s}
      end
    end
  end
end
