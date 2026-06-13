# frozen_string_literal: true

require_relative "retriable/config"
require_relative "retriable/exponential_backoff"
require_relative "retriable/version"

module Retriable
  # Thread-local storage key for the active #with_override block.
  # We deliberately use Thread#thread_variable_set/get (true thread-local)
  # rather than Thread.current[] (fiber-local) so that fibers within a thread
  # share the same override. Changing this to Thread.current[] would silently
  # break callers that use fiber-based concurrency.
  OVERRIDE_THREAD_KEY = :retriable_override

  RetryPlan = Struct.new(:max_tries, :interval_for)
  private_constant :RetryPlan

  module_function

  def configure
    yield(config)
  end

  def config
    @config ||= Config.new
  end

  def with_override(opts = {})
    raise ArgumentError, "empty override options are not allowed" if opts.empty?
    raise ArgumentError, "with_override requires a block" unless block_given?

    validate_override_options(opts)

    previous = Thread.current.thread_variable_get(OVERRIDE_THREAD_KEY)
    Thread.current.thread_variable_set(OVERRIDE_THREAD_KEY, opts)
    begin
      yield
    ensure
      Thread.current.thread_variable_set(OVERRIDE_THREAD_KEY, previous)
    end
  end

  def with_context(context_key, options = {}, &)
    contexts = available_contexts

    if !contexts.key?(context_key)
      raise ArgumentError,
            "#{context_key} not found in Retriable contexts (including overrides). Available contexts: #{contexts.keys}"
    end

    return unless block_given?

    retriable(context_options_for(context_key, options), &)
  end

  def retriable(opts = {}, &)
    override_config = current_override
    local_config = if opts.empty? && !override_config
                     config
                   else
                     Config.new(apply_override_options(merge_layer(config.to_h, opts), override_config))
                   end

    # Config is mutable through `configure`, so validate again immediately before use.
    local_config.validate!

    plan = retry_plan(local_config)
    on = local_config.on
    retry_if = local_config.retry_if
    on_retry = local_config.on_retry
    on_give_up = local_config.on_give_up
    sleep_disabled = local_config.sleep_disabled
    max_elapsed_time = local_config.max_elapsed_time

    exception_list = on.is_a?(Hash) ? on.keys : on
    exception_list = [*exception_list]
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_time = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time }

    execute_tries(
      max_tries: plan.max_tries, interval_for: plan.interval_for,
      exception_list: exception_list, on: on, retry_if: retry_if, on_retry: on_retry,
      on_give_up: on_give_up, elapsed_time: elapsed_time, max_elapsed_time: max_elapsed_time,
      sleep_disabled: sleep_disabled, &
    )
  end

  def execute_tries( # rubocop:disable Metrics/ParameterLists
    max_tries:, interval_for:, exception_list:,
    on:, retry_if:, on_retry:, on_give_up:, elapsed_time:, max_elapsed_time:, sleep_disabled:
  )
    try = 0
    loop do
      try += 1
      begin
        return yield(try)
      rescue *exception_list => e
        raise unless retriable_exception?(e, on, exception_list, retry_if)

        # On the final attempt `interval_for` returns nil (no next retry), and
        # `on_retry` intentionally fires before the give-up check below, so it
        # receives `interval: nil`. See the on_retry/on_give_up README contract.
        interval = interval_for.call(try - 1)
        call_on_retry(on_retry, e, try, elapsed_time.call, interval)

        elapsed_interval = sleep_disabled == true ? 0 : interval
        # Snapshot elapsed_time once so the stop check and on_give_up see the same value.
        current_elapsed_time = elapsed_time.call
        stop_reason = retry_stop_reason(try, max_tries, current_elapsed_time, elapsed_interval, max_elapsed_time)
        if stop_reason
          call_on_give_up(on_give_up, e, try, current_elapsed_time, interval, stop_reason)
          raise
        end

        sleep interval if sleep_disabled != true
      end
    end
  end

  def retry_plan(local_config)
    return RetryPlan.new(nil, interval_provider(local_config)) if Validation.unbounded_tries?(local_config.tries)

    if local_config.intervals
      intervals = local_config.intervals
      return RetryPlan.new(intervals.size + 1, ->(index) { intervals[index] })
    end

    max_tries = local_config.tries
    provider = interval_provider(local_config)

    RetryPlan.new(max_tries, ->(index) { index < max_tries - 1 ? provider.call(index) : nil })
  end

  def interval_provider(local_config)
    ExponentialBackoff.new(
      base_interval: local_config.base_interval,
      multiplier: local_config.multiplier,
      max_interval: local_config.max_interval,
      rand_factor: local_config.rand_factor,
    ).interval_provider
  end

  def call_on_retry(on_retry, exception, try, elapsed_time, interval)
    return unless on_retry

    on_retry.call(exception, try, elapsed_time, interval)
  end

  def call_on_give_up( # rubocop:disable Metrics/ParameterLists
    on_give_up, exception, try, elapsed_time, interval, reason
  )
    return unless on_give_up

    on_give_up.call(exception, try, elapsed_time, interval, reason)
  end

  # `:tries_exhausted` is checked first, but the two conditions can't both hold
  # on the same try in practice: `retry_plan` returns a nil interval whenever
  # `try >= max_tries`, so `(elapsed_time + interval) > max_elapsed_time` is not
  # evaluable on the exhausted-tries try. The early return guards against that
  # nil and also pins precedence in case the plan ever changes.
  def retry_stop_reason(try, max_tries, elapsed_time, interval, max_elapsed_time)
    return :tries_exhausted if max_tries && try >= max_tries
    return nil if max_elapsed_time.nil?

    :max_elapsed_time if (elapsed_time + interval) > max_elapsed_time
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

    return unless opts.key?(:contexts)

    contexts = opts[:contexts]
    return if contexts.nil?

    raise ArgumentError, "contexts must be a Hash or nil, got #{contexts.inspect}" unless contexts.is_a?(Hash)

    contexts.each do |context_key, context_options|
      validate_context_override_options(context_key, context_options)
    end
  end

  def validate_context_override_options(context_key, context_options)
    unless context_options.is_a?(Hash)
      raise ArgumentError,
            "contexts[#{context_key.inspect}] must be a Hash, got #{context_options.inspect}"
    end

    context_attributes = Config::ATTRIBUTES - [:contexts]
    context_options.each_key do |k|
      raise ArgumentError, "#{k} is not a valid option" unless context_attributes.include?(k)
    end
  end

  def apply_override_options(options, overrides)
    return options unless overrides

    merge_layer(options, overrides)
  end

  # Merge a higher-precedence option layer onto a base layer. A higher layer
  # that sets `tries` without `intervals` clears the base layer's inherited
  # `intervals`, so a caller's `tries:` is never silently ignored. When the
  # higher layer supplies its own `intervals`, those win (same-call override).
  def merge_layer(base, higher)
    merged = base.merge(higher)
    merged[:intervals] = nil if higher.key?(:tries) && !higher.key?(:intervals)
    merged
  end

  def available_contexts
    config_contexts.merge(override_contexts)
  end

  def context_options_for(context_key, options)
    context_options = config_contexts.fetch(context_key, {})
    context_options = {} unless context_options.is_a?(Hash)
    context_options = merge_layer(context_options, options)

    override_context_options = override_contexts[context_key]
    return context_options unless override_context_options.is_a?(Hash)

    apply_override_options(context_options, override_context_options)
  end

  def config_contexts
    config.contexts.is_a?(Hash) ? config.contexts : {}
  end

  def override_contexts
    override_config = current_override
    contexts = override_config && override_config[:contexts]
    contexts.is_a?(Hash) ? contexts : {}
  end

  def current_override
    Thread.current.thread_variable_get(OVERRIDE_THREAD_KEY)
  end

  private_class_method(
    :validate_override_options,
    :validate_context_override_options,
    :execute_tries,
    :retry_plan,
    :interval_provider,
    :call_on_retry,
    :call_on_give_up,
    :retry_stop_reason,
    :retriable_exception?,
    :hash_exception_match?,
    :apply_override_options,
    :merge_layer,
    :available_contexts,
    :context_options_for,
    :config_contexts,
    :override_contexts,
    :current_override,
  )
end
