require "timeout"
require_relative "retriable/config"
require_relative "retriable/exponential_backoff"
require_relative "retriable/version"

module Retriable
  extend self

  attr_reader :config

  def self.configure
    yield(config)
  end

  def config
    @config ||= Config.new
  end

  def retriable(opts = {})
    tries             = opts[:tries]            || config.tries
    base_interval     = opts[:base_interval]    || config.base_interval
    max_interval      = opts[:max_interval]     || config.max_interval
    rand_factor       = opts[:rand_factor]      || config.rand_factor
    multiplier        = opts[:multiplier]       || config.multiplier
    max_elapsed_time  = opts[:max_elapsed_time] || config.max_elapsed_time
    intervals         = opts[:intervals]        || config.intervals
    timeout           = opts[:timeout]          || config.timeout
    on                = opts[:on]               || config.on
    on_retry          = opts[:on_retry]         || config.on_retry

    start_time = Time.now
    elapsed_time = -> { Time.now - start_time }

    if intervals
      tries = intervals.size + 1
    else
      intervals = ExponentialBackoff.new(
        tries:          tries - 1,
        base_interval:  base_interval,
        multiplier:     multiplier,
        max_interval:   max_interval,
        rand_factor:    rand_factor
      ).intervals
    end

    exception_list = on.kind_of?(Hash) ? on.keys : on

    tries.times do |index|
      try = index + 1
      begin
        if timeout
          Timeout::timeout(timeout) { return yield(try) }
        else
          return yield(try)
        end
      rescue *[*exception_list] => exception
        if on.kind_of?(Hash)
          patterns = [*on[exception.class]]
          message_match = patterns.empty? ? true : false
          patterns.each do |pattern|
            if !!(exception.message =~ pattern)
              message_match = true
              break
            end
          end
          raise unless message_match
        end

        interval = intervals[index]
        on_retry.call(exception, try, elapsed_time.call, interval) if on_retry
        raise if try >= tries || (elapsed_time.call + interval) > max_elapsed_time
        sleep interval if config.sleep_disabled != true
      end
    end
  end
end
