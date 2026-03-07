# frozen_string_literal: true

require_relative "validation"

module Retriable
  class ExponentialBackoff
    include Validation

    ATTRIBUTES = %i[
      tries
      base_interval
      multiplier
      max_interval
      rand_factor
    ].freeze

    attr_accessor(*ATTRIBUTES)

    def initialize(opts = {})
      @tries         = 3
      @base_interval = 0.5
      @max_interval  = 60
      @rand_factor   = 0.5
      @multiplier    = 1.5

      opts.each do |k, v|
        raise ArgumentError, "#{k} is not a valid option" if !ATTRIBUTES.include?(k)

        instance_variable_set(:"@#{k}", v)
      end

      validate!
    end

    def intervals
      Array.new(tries) { |iteration| interval_for(iteration) }
    end

    def interval_for(iteration)
      interval = [base_interval * (multiplier**iteration), max_interval].min
      return interval if rand_factor.zero?

      randomize(interval)
    end

    private

    def validate!
      validate_non_negative_integer(:tries, tries)
      validate_non_negative_number(:base_interval, base_interval)
      validate_non_negative_number(:multiplier, multiplier)
      validate_non_negative_number(:max_interval, max_interval)
      validate_rand_factor
    end

    def randomize(interval)
      delta = rand_factor * interval.to_f
      min = interval - delta
      max = interval + delta
      rand(min..max)
    end
  end
end
