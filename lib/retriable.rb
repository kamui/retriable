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

  def with_context(context_key, options = {}, &block)
    if !config.contexts.key?(context_key)
      raise ArgumentError,
            "#{context_key} not found in Retriable.config.contexts. Available contexts: #{config.contexts.keys}"
    end

    return unless block_given?

    retriable(config.contexts[context_key].merge(options), &block)
  end

  def retriable(opts = {}, &block)
    local_config = opts.empty? ? config : Config.new(config.to_h.merge(opts))

    tries = local_config.tries
    intervals = build_intervals(local_config, tries)
    timeout = local_config.timeout
    on = local_config.on
    on_retry = local_config.on_retry
    sleep_disabled = local_config.sleep_disabled
    max_elapsed_time = local_config.max_elapsed_time

    exception_list = on.is_a?(Hash) ? on.keys : on
    start_time = Time.now
    elapsed_time = -> { Time.now - start_time }

    tries = intervals.size + 1

    execution_context = {
      tries: tries,
      intervals: intervals,
      timeout: timeout,
      exception_list: exception_list,
      on: on,
      on_retry: on_retry,
      elapsed_time: elapsed_time,
      max_elapsed_time: max_elapsed_time,
      sleep_disabled: sleep_disabled
    }

    execute_tries(execution_context, &block)
  end

  def execute_tries(execution_context, &block)
    tries = execution_context[:tries]
    intervals = execution_context[:intervals]
    timeout = execution_context[:timeout]
    exception_list = execution_context[:exception_list]
    on = execution_context[:on]
    on_retry = execution_context[:on_retry]
    elapsed_time = execution_context[:elapsed_time]
    max_elapsed_time = execution_context[:max_elapsed_time]
    sleep_disabled = execution_context[:sleep_disabled]

    tries.times do |index|
      try = index + 1

      begin
        return call_with_timeout(timeout, try, &block)
      rescue *exception_list => e
        raise unless retriable_exception?(e, on, exception_list)

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
    try < tries && (elapsed_time + interval) <= max_elapsed_time
  end

  def retriable_exception?(exception, on, exception_list)
    return false if on.is_a?(Hash) && !hash_exception_match?(exception, on, exception_list)

    true
  end

  def hash_exception_match?(exception, on, exception_list)
    exception_list.any? do |error_class|
      next false unless exception.is_a?(error_class)

      patterns = [*on[error_class]]
      patterns.empty? || patterns.any? { |pattern| exception.message =~ pattern }
    end
  end

  private_class_method :execute_tries,
                       :build_intervals,
                       :call_with_timeout,
                       :call_on_retry,
                       :can_retry?,
                       :retriable_exception?,
                       :hash_exception_match?
end
