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
      raise ArgumentError, "#{context_key} not found in Retriable.config.contexts. Available contexts: #{config.contexts.keys}"
    end

    retriable(config.contexts[context_key].merge(options), &block) if block
  end

  def retriable(opts = {})
    local_config = opts.empty? ? config : Config.new(config.to_h.merge(opts))

    tries             = local_config.tries
    base_interval     = local_config.base_interval
    max_interval      = local_config.max_interval
    rand_factor       = local_config.rand_factor
    multiplier        = local_config.multiplier
    max_elapsed_time  = local_config.max_elapsed_time
    intervals         = local_config.intervals
    timeout           = local_config.timeout
    on                = local_config.on
    on_retry          = local_config.on_retry
    sleep_disabled    = local_config.sleep_disabled

    exception_list = on.is_a?(Hash) ? on.keys : on
    start_time = Time.now
    elapsed_time = -> { Time.now - start_time }

    if intervals
      tries = intervals.size + 1 if intervals.size
    else
      backoff = ExponentialBackoff.new(
        tries:          tries ? tries - 1 : nil,
        base_interval:  base_interval,
        multiplier:     multiplier,
        max_interval:   max_interval,
        rand_factor:    rand_factor,
      )
      intervals = backoff.intervals
    end

    # TODO: Ideally this would be it's own function, but would probably require
    #   a separate class to efficiently pass on the processed config
    run_try = Proc.new do |interval, try|
      begin
        return Timeout.timeout(timeout) { return yield(try) } if timeout
        return yield(try)
      rescue *exception_list => exception
        if on.is_a?(Hash)
          raise unless exception_list.any? do |e|
            exception.is_a?(e) && ([*on[e]].empty? || [*on[e]].any? { |pattern| exception.message =~ pattern })
          end
        end
        on_retry.call(exception, try, elapsed_time.call, interval) if on_retry


        # Note: Tries can't always be calculated if a custom Enumerator is given
        #   for the intervals argument. (Enumerator#size will return nil, per docs)
        #   So we'll just let the enumerator run out, and then invoke run_try once more.
        #   With a nil timeout.
        raise unless interval
        raise if max_elapsed_time && elapsed_time.call + interval > max_elapsed_time
        sleep interval unless sleep_disabled
        throw :failed
      end
    end

    try = 0
    intervals.each do |interval|
      try += 1
      # Use throw/catch to distinguish between success and caught exception
      catch :failed do
        result = run_try.call(interval, try)
        return result
      end
      break if tries and try + 1 >= tries
    end
    run_try.call(nil, try + 1)
  end
end
