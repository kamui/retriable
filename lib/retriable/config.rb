# frozen_string_literal: true

require_relative "exponential_backoff"

module Retriable
  class Config
    ATTRIBUTES = (ExponentialBackoff::ATTRIBUTES + %i[
      sleep_disabled
      max_elapsed_time
      intervals
      timeout
      on
      retry_if
      on_retry
      contexts
    ]).freeze

    attr_accessor(*ATTRIBUTES)

    def initialize(opts = {})
      backoff = ExponentialBackoff.new

      @tries            = backoff.tries
      @base_interval    = backoff.base_interval
      @max_interval     = backoff.max_interval
      @rand_factor      = backoff.rand_factor
      @multiplier       = backoff.multiplier
      @sleep_disabled   = false
      @max_elapsed_time = 900 # 15 min
      @intervals        = nil
      @timeout          = nil
      @on               = [StandardError]
      @retry_if         = nil
      @on_retry         = nil
      @contexts         = {}

      opts.each do |k, v|
        raise ArgumentError, "#{k} is not a valid option" if !ATTRIBUTES.include?(k)

        instance_variable_set(:"@#{k}", v)
      end

      validate!
    end

    def to_h
      ATTRIBUTES.each_with_object({}) do |key, hash|
        hash[key] = public_send(key)
      end
    end

    def validate!
      validate_positive_integer(:tries, tries)
      validate_non_negative_number(:base_interval, base_interval)
      validate_non_negative_number(:multiplier, multiplier)
      validate_non_negative_number(:max_interval, max_interval)
      validate_rand_factor
      validate_optional_non_negative_number(:max_elapsed_time, max_elapsed_time)
      validate_optional_non_negative_number(:timeout, timeout)
      validate_intervals
    end

    private

    def validate_positive_integer(name, value)
      return if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{name} must be a positive integer"
    end

    def validate_non_negative_number(name, value)
      return if finite_number?(value) && value >= 0

      raise ArgumentError, "#{name} must be a non-negative number"
    end

    def validate_optional_non_negative_number(name, value)
      return if value.nil?

      validate_non_negative_number(name, value)
    end

    def validate_rand_factor
      return if finite_number?(rand_factor) && rand_factor >= 0 && rand_factor <= 1

      raise ArgumentError, "rand_factor must be between 0 and 1"
    end

    def validate_intervals
      return if intervals.nil?
      raise ArgumentError, "intervals must be an Array" unless intervals.is_a?(Array)
      return if intervals.all? { |interval| finite_number?(interval) && interval >= 0 }

      raise ArgumentError, "intervals must contain only non-negative numbers"
    end

    def finite_number?(value)
      value.is_a?(Numeric) && value.to_f.finite?
    end
  end
end
