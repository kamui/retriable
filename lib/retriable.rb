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
    on_retry:          config.on_retry,
    &block
    )

    raise LocalJumpError unless block_given?

    start_time = Time.now
    elapsed_time = -> { Time.now - start_time }

    max_tries = intervals.size if intervals
    intervals ||= ExponentialBackoff.new(
      max_tries: max_tries,
      base_interval: base_interval,
      multiplier: multiplier,
      max_interval: max_interval,
      rand_factor: rand_factor
    ).intervals

    filter = rescue_filter(on)

    intervals.each.with_index(1) do |interval, attempt|
      begin
        if timeout
          Timeout::timeout(timeout) { return block.call(attempt) }
        else
          return block.call(attempt)
        end
      rescue *[*rescue_klasses(on)] => exception
        raise if filter[exception.class] && exception.message !~ filter[exception.class]
        on_retry.call(exception, attempt, Time.now - start_time, interval) if on_retry
        raise if attempt >= max_tries || (elapsed_time.call + interval) > max_elapsed_time
        sleep interval if config.sleep_disabled != true
      end
    end
  end

  private

  def rescue_klasses(on)
    Array(on).map do |element|
      element.is_a?(Hash) ? element[:klass] : element
    end
  end

  def rescue_filter(on)
    Array(on).inject({}) do |h, element|
      if element.is_a?(Hash)
        h[element[:klass]] = element[:regex]
      end
      h
    end
  end
end
