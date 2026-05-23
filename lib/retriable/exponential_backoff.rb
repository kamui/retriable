# frozen_string_literal: true

module Retriable
  class ExponentialBackoff
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
      Array.new(tries) { |iteration| interval_at(iteration) }
    end

    def interval_at(iteration)
      interval = [base_interval * (multiplier**iteration), max_interval].min

      rand_factor.zero? ? interval : randomize(interval)
    end

    private

    def validate!
      validate_positive_integer(:tries, tries)
      validate_non_negative_number(:base_interval, base_interval)
      validate_non_negative_number(:multiplier, multiplier)
      validate_non_negative_number(:max_interval, max_interval)
      validate_rand_factor
    end

    def validate_positive_integer(name, value)
      return if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{name} must be a positive integer"
    end

    def validate_non_negative_number(name, value)
      return if finite_number?(value) && value >= 0

      raise ArgumentError, "#{name} must be a non-negative number"
    end

    def validate_rand_factor
      return if finite_number?(rand_factor) && rand_factor >= 0 && rand_factor <= 1

      raise ArgumentError, "rand_factor must be between 0 and 1"
    end

    def finite_number?(value)
      value.is_a?(Numeric) && value.to_f.finite?
    end

    def randomize(interval)
      delta = rand_factor * interval.to_f
      min = interval - delta
      max = interval + delta
      rand(min..max)
    end
  end
end
