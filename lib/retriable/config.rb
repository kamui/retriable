# frozen_string_literal: true

require_relative "exponential_backoff"
require_relative "validation"

module Retriable
  class Config
    include Validation

    ATTRIBUTES = (ExponentialBackoff::ATTRIBUTES + %i[
      sleep_disabled
      max_elapsed_time
      intervals
      on
      retry_if
      on_retry
      on_give_up
      contexts
    ]).freeze

    CONTEXT_ATTRIBUTES = (ATTRIBUTES - %i[contexts]).freeze
    private_constant :CONTEXT_ATTRIBUTES

    attr_accessor(*ATTRIBUTES)

    def initialize(opts = {})
      defaults = ExponentialBackoff::DEFAULTS

      @tries            = defaults[:tries]
      @base_interval    = defaults[:base_interval]
      @max_interval     = defaults[:max_interval]
      @rand_factor      = defaults[:rand_factor]
      @multiplier       = defaults[:multiplier]
      @sleep_disabled   = false
      @max_elapsed_time = 900 # 15 min
      @intervals        = nil
      @on               = [StandardError]
      @retry_if         = nil
      @on_retry         = nil
      @on_give_up       = nil
      @contexts         = {}

      opts.each do |k, v|
        raise ArgumentError, "#{k} is not a valid option" if !ATTRIBUTES.include?(k)

        instance_variable_set(:"@#{k}", v)
      end

      validate!
    end

    def to_h
      ATTRIBUTES.to_h { |key| [key, public_send(key)] }
    end

    def validate!
      validate_contexts
      validate_callable(:retry_if, retry_if)
      validate_callable(:on_retry, on_retry)
      validate_callable(:on_give_up, on_give_up)
      validate_on(on)
      validate_intervals
      if unbounded_tries?(tries)
        validate_unbounded_tries
      else
        validate_optional_non_negative_number(:max_elapsed_time, max_elapsed_time)
        return if intervals

        validate_positive_integer(:tries, tries)
      end

      validate_backoff_options
    end

    private

    def validate_contexts
      return unless contexts.is_a?(Hash)
      return if contexts.empty?

      contexts.each_value do |options|
        next unless options.is_a?(Hash)

        options.each_key do |k|
          next if CONTEXT_ATTRIBUTES.include?(k)

          raise ArgumentError, "#{k} is not a valid option"
        end
      end
    end

    def validate_backoff_options
      validate_non_negative_number(:base_interval, base_interval)
      validate_non_negative_number(:multiplier, multiplier)
      validate_non_negative_number(:max_interval, max_interval)
      validate_rand_factor
    end

    def validate_unbounded_tries
      if intervals
        raise ArgumentError,
              "intervals cannot be used with tries: Float::INFINITY"
      end

      unless finite_number?(max_elapsed_time)
        raise ArgumentError,
              "max_elapsed_time must be a finite number when tries is Float::INFINITY"
      end

      validate_non_negative_number(:max_elapsed_time, max_elapsed_time)
    end

    def validate_intervals
      return if intervals.nil?
      raise ArgumentError, "intervals must be an Array" unless intervals.is_a?(Array)
      return if intervals.all? { |interval| finite_number?(interval) && interval >= 0 }

      raise ArgumentError, "intervals must contain only non-negative numbers"
    end
  end
end
