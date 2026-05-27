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
      timeout
      on
      retry_if
      on_retry
      contexts
    ]).freeze

    TIMEOUT_DEPRECATION_MESSAGE = "Retriable: the `timeout:` option is deprecated and will be removed in " \
                                  "Retriable 4.0. It is a thin wrapper around `Timeout.timeout`, which " \
                                  "can interrupt execution at arbitrary lines and corrupt internal state " \
                                  "in libraries that are not interrupt-safe. Prefer your library's native " \
                                  "timeout, or wrap your block in `Timeout.timeout(...)` yourself."
    private_constant :TIMEOUT_DEPRECATION_MESSAGE

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
      warn_timeout_deprecation
      validate_optional_non_negative_number(:timeout, timeout)
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

    def warn_timeout_deprecation
      return if timeout.nil?

      if deprecated_warning_category_enabled?
        Kernel.warn(TIMEOUT_DEPRECATION_MESSAGE, category: :deprecated)
      else
        Kernel.warn(TIMEOUT_DEPRECATION_MESSAGE)
      end
    end

    def deprecated_warning_category_enabled?
      return false unless Kernel.method(:warn).parameters.any? { |type, name| type == :key && name == :category }
      return false unless Warning.respond_to?(:[])

      Warning[:deprecated]
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
