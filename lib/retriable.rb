require "timeout"
require "retriable/config"
require "retriable/exponential_backoff"
require "retriable/version"

module Retriable
  extend self

  attr_reader :config

  def self.configure
    yield(config)
  end

  def config
    @config ||= Config.new
  end

  def retry(
    max_tries:         config.max_tries,
    base_interval:     config.base_interval,
    max_interval:      config.max_interval,
    rand_factor:       config.rand_factor,
    multiplier:        config.multiplier,
    max_elapsed_time:  config.max_elapsed_time,
    intervals:         config.intervals,
    timeout:           config.timeout,
    on:                config.on,
    on_retry:          config.on_retry
    )

    start_time = Time.now
    elapsed_time = -> { Time.now - start_time }

    if intervals
      max_tries = intervals.size
    else
      intervals = ExponentialBackoff.new(
        max_tries: max_tries,
        base_interval: base_interval,
        multiplier: multiplier,
        max_interval: max_interval,
        rand_factor: rand_factor
      ).intervals
    end

    exception_list = on.kind_of?(Hash) ? on.keys : on

    intervals.each.with_index(1) do |interval, attempt|
      begin
        if timeout
          Timeout::timeout(timeout) { return yield(attempt) }
        else
          return yield(attempt)
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

        on_retry.call(exception, attempt, elapsed_time.call, interval) if on_retry
        raise if attempt >= max_tries || (elapsed_time.call + interval) > max_elapsed_time
        sleep interval if config.sleep_disabled != true
      end
    end
  end
end
