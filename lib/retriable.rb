require "timeout"
require_relative "retriable/config"
require_relative "retriable/environment"
require_relative "retriable/exponential_backoff"
require_relative "retriable/version"

module Retriable
  module_function

  def configure
    yield(config)
    config.validate!
  end

  def config
    @config ||= Config.new
  end

  def reset!
    @config = Config.new
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
        rand_factor:    rand_factor,
      ).intervals
    end

    exception_list = on.is_a?(Hash) ? on.keys : on

    tries.times do |index|
      try = index + 1
      begin
        return Timeout.timeout(timeout) { return yield(try) } if timeout
        return yield(try)
      rescue *[*exception_list] => exception
        if on.is_a?(Hash)
          raise unless exception_list.any? do |e|
            exception.is_a?(e) && ([*on[e]].empty? || [*on[e]].any? { |pattern| exception.message =~ pattern })
          end
        end

        interval = intervals[index]
        on_retry.call(exception, try, elapsed_time.call, interval) if on_retry
        raise if try >= tries || (elapsed_time.call + interval) > max_elapsed_time
        sleep interval if sleep_disabled != true
      end
    end
  end

  def respond_to?(method_sym, options = {}, &block)
    super || config.environments.key?(method_sym)
  end

  def method_missing(method_sym, options = {}, &block)
    if config.environments.key?(method_sym)
      config.environments[method_sym]
    else
      super
    end
  end
end
