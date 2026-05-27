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

    TIMEOUT_DEPRECATION_MESSAGE = "NOTE: Retriable's `timeout:` option is deprecated and will be removed in " \
                                  "Retriable 4.0. It is a thin wrapper around `Timeout.timeout`, which " \
                                  "can interrupt execution at arbitrary lines and corrupt internal state " \
                                  "in libraries that are not interrupt-safe. Prefer your library's native " \
                                  "timeout, or wrap your block in `Timeout.timeout(...)` yourself."
    private_constant :TIMEOUT_DEPRECATION_MESSAGE

    @timeout_deprecation_warned = false

    class << self
      attr_accessor :timeout_deprecation_warned
    end

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

    # Emits the `timeout:` deprecation notice at most once per process.
    #
    # On Rubies that support `Kernel#warn(category: :deprecated)` (2.7+), the
    # notice is emitted under the `:deprecated` category, so callers can use the
    # standard controls (`Warning[:deprecated] = false`, `-W:no-deprecated`,
    # `Warning.warn` override) to silence it. On older Rubies the kwarg is not
    # available and we fall back to plain `Kernel.warn`.
    #
    # When the warning is suppressed (either because `Warning[:deprecated]` is
    # false or the runtime has otherwise muted the category), we deliberately
    # leave the once-per-process flag unset so a future call with the category
    # re-enabled still surfaces the notice.
    def warn_timeout_deprecation
      return if timeout.nil?
      return if self.class.timeout_deprecation_warned

      category_supported = deprecated_warning_category_supported?
      return if category_supported && !deprecated_warnings_enabled?

      self.class.timeout_deprecation_warned = true
      if category_supported
        Kernel.warn(TIMEOUT_DEPRECATION_MESSAGE, category: :deprecated)
      else
        Kernel.warn(TIMEOUT_DEPRECATION_MESSAGE)
      end
    end

    def deprecated_warning_category_supported?
      defined?(Warning) && Kernel.method(:warn).parameters.any? { |type, name| type == :key && name == :category }
    end

    def deprecated_warnings_enabled?
      return true unless defined?(Warning) && Warning.respond_to?(:[])

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
