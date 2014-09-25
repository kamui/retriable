require 'timeout'
require 'retriable/config'
require 'retriable/version'

module Retriable
  extend self

  attr_accessor :config

  def self.configure
    self.config ||= Config.new
    yield(config)
  end

  def retry(
    max_tries:         config.max_tries,
    base_interval:     config.base_interval,
    max_interval:      config.max_interval,
    rand_factor:       config.rand_factor,
    multiplier:        config.multiplier,
    max_elapsed_time:  config.max_elapsed_time,
    timeout:           config.timeout,
    on:                config.on,
    on_retry:          config.on_retry,
    &block)

    raise LocalJumpError unless block_given?

    attempt = 0
    interval = base_interval
    start_time = Time.now
    elapsed_time = lambda { Time.now - start_time }

    begin
      attempt += 1
      if timeout
        Timeout::timeout(timeout) { return block.call(attempt) }
      else
        return block.call(attempt)
      end
    rescue *[*on] => exception
      raise if attempt >= max_tries

      interval = randomized_interval(rand_factor, interval)

      on_retry.call(exception, attempt, Time.now - start_time, interval) if on_retry

      raise if elapsed_time.call > max_elapsed_time || (elapsed_time.call + interval) > max_elapsed_time

      sleep interval if interval > 0 && config.sleep_disabled != true

      interval = if interval >= (max_interval / multiplier)
        max_interval
      else
        interval * multiplier
      end

      retry
    end
  end

  private
  def randomized_interval(rand_factor, interval)
    return interval if rand_factor == 0
    delta = rand_factor * interval * 1.0
    min_interval = interval - delta
    max_interval = interval + delta
    rand(min_interval..max_interval)
  end
end
