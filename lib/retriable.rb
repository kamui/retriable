# frozen_string_literal: true

require "timeout"
require_relative "retriable/config"
require_relative "retriable/exponential_backoff"
require_relative "retriable/version"

module Retriable
  module_function

  def configure
    yield(config)
  end

  def config
    @config ||= Config.new
  end

  def override(opts = {})
    raise ArgumentError, "empty override options are not allowed; use reset_override instead" if opts.empty?

    validate_override_options(opts)
    @override_config = opts
  end

  def reset_override
    @override_config = nil
  end

  def with_context(context_key, options = {}, &block)
    contexts = available_contexts

    if !contexts.key?(context_key)
      raise ArgumentError,
            "#{context_key} not found in Retriable contexts (including overrides). Available contexts: #{contexts.keys}"
    end

    return unless block_given?

    retriable(context_options_for(context_key, options), &block)
  end

  def retriable(opts = {}, &block)
    local_config = if opts.empty? && !@override_config
                     config
                   else
                     Config.new(apply_override_options(config.to_h.merge(opts), @override_config))
                   end

    tries = local_config.tries
    intervals = build_intervals(local_config, tries)
    timeout = local_config.timeout
    on = local_config.on
    retry_if = local_config.retry_if
    on_retry = local_config.on_retry
    sleep_disabled = local_config.sleep_disabled
    max_elapsed_time = local_config.max_elapsed_time

    exception_list = on.is_a?(Hash) ? on.keys : on
    exception_list = [*exception_list]
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_time = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time }

    tries = intervals.size + 1

    execute_tries(
      tries: tries, intervals: intervals, timeout: timeout,
      exception_list: exception_list, on: on, retry_if: retry_if, on_retry: on_retry,
      elapsed_time: elapsed_time, max_elapsed_time: max_elapsed_time,
      sleep_disabled: sleep_disabled, &block
    )
  end

  def execute_tries( # rubocop:disable Metrics/ParameterLists
    tries:, intervals:, timeout:, exception_list:,
    on:, retry_if:, on_retry:, elapsed_time:, max_elapsed_time:, sleep_disabled:, &block
  )
    tries.times do |index|
      try = index + 1

      begin
        return call_with_timeout(timeout, try, &block)
      rescue *exception_list => e
        raise unless retriable_exception?(e, on, exception_list, retry_if)

        interval = intervals[index]
        call_on_retry(on_retry, e, try, elapsed_time.call, interval)

        raise unless can_retry?(try, tries, elapsed_time.call, interval, max_elapsed_time)

        sleep interval if sleep_disabled != true
      end
    end
  end

  def build_intervals(local_config, tries)
    return local_config.intervals if local_config.intervals

    ExponentialBackoff.new(
      tries: tries - 1,
      base_interval: local_config.base_interval,
      multiplier: local_config.multiplier,
      max_interval: local_config.max_interval,
      rand_factor: local_config.rand_factor,
    ).intervals
  end

  def call_with_timeout(timeout, try)
    return Timeout.timeout(timeout) { yield(try) } if timeout

    yield(try)
  end

  def call_on_retry(on_retry, exception, try, elapsed_time, interval)
    return unless on_retry

    on_retry.call(exception, try, elapsed_time, interval)
  end

  def can_retry?(try, tries, elapsed_time, interval, max_elapsed_time)
    return false unless try < tries
    return true if max_elapsed_time.nil?

    (elapsed_time + interval) <= max_elapsed_time
  end

  # When `on` is a Hash, we need to verify the exception matches a pattern.
  # For any non-Hash `on` value (e.g., Array of classes, single Exception class,
  # or Module), the `rescue *exception_list` clause already guarantees the
  # exception is retriable with respect to `on`; `retry_if`, if provided, is an
  # additional gate that can still cause this method to return false.
  def retriable_exception?(exception, on, exception_list, retry_if)
    return false if on.is_a?(Hash) && !hash_exception_match?(exception, on, exception_list)
    return false if retry_if && !retry_if.call(exception)

    true
  end

  def hash_exception_match?(exception, on, exception_list)
    exception_list.any? do |error_class|
      next false unless exception.is_a?(error_class)

      patterns = [*on[error_class]]
      patterns.empty? || patterns.any? { |pattern| exception.message =~ pattern }
    end
  end

  def validate_override_options(opts)
    opts.each_key do |k|
      raise ArgumentError, "#{k} is not a valid option" unless Config::ATTRIBUTES.include?(k)
    end

    contexts = opts[:contexts]
    return unless contexts.is_a?(Hash)

    contexts.each_value do |context_options|
      validate_context_override_options(context_options)
    end
  end

  def validate_context_override_options(context_options)
    return unless context_options.is_a?(Hash)

    context_attributes = Config::ATTRIBUTES - [:contexts]
    context_options.each_key do |k|
      raise ArgumentError, "#{k} is not a valid option" unless context_attributes.include?(k)
    end
  end

  def apply_override_options(options, overrides)
    return options unless overrides

    options = options.merge(overrides)
    options[:intervals] = nil if overrides.key?(:tries) && !overrides.key?(:intervals)
    options
  end

  def available_contexts
    config_contexts.merge(override_contexts)
  end

  def context_options_for(context_key, options)
    context_options = config_contexts.fetch(context_key, {})
    context_options = {} unless context_options.is_a?(Hash)
    context_options = context_options.merge(options)

    override_context_options = override_contexts[context_key]
    return context_options unless override_context_options.is_a?(Hash)

    apply_override_options(context_options, override_context_options)
  end

  def config_contexts
    config.contexts.is_a?(Hash) ? config.contexts : {}
  end

  def override_contexts
    contexts = @override_config && @override_config[:contexts]
    contexts.is_a?(Hash) ? contexts : {}
  end

  private_class_method(
    :validate_override_options,
    :validate_context_override_options,
    :execute_tries,
    :build_intervals,
    :call_with_timeout,
    :call_on_retry,
    :can_retry?,
    :retriable_exception?,
    :hash_exception_match?,
    :apply_override_options,
    :available_contexts,
    :context_options_for,
    :config_contexts,
    :override_contexts,
  )
end
