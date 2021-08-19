# frozen_string_literal: true

require "timeout"
require_relative "retriable/config"
require_relative "retriable/exponential_backoff"
require_relative "retriable/version"

module Retriable
  class << self
    def configure
      yield(config)
    end

    def config
      @config ||= Config.new
    end

    def with_context(context_key, options = {}, &block)
      if !config.contexts.key?(context_key)
        raise ArgumentError, "#{context_key} not found in Retriable.config.contexts. "\
          "Available contexts: #{config.contexts.keys}"
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
      not_              = local_config.not
      on_retry          = local_config.on_retry
      sleep_disabled    = local_config.sleep_disabled

      on_exceptions = on.is_a?(Hash) ? on.keys : on
      not_exceptions = not_.is_a?(Hash) ? not_.keys : not_
      start_time = Time.now
      elapsed_time = -> { Time.now - start_time }

      if intervals
        tries = intervals.size + 1
      else
        intervals = ExponentialBackoff.new(
          tries: tries - 1,
          base_interval: base_interval,
          multiplier: multiplier,
          max_interval: max_interval,
          rand_factor: rand_factor,
        ).intervals
      end

      tries.times do |index|
        try = index + 1

        begin
          return Timeout.timeout(timeout) { return yield(try) } if timeout

          return yield(try)
        rescue *not_exceptions => e
          raise if !not_.is_a?(Hash) || matches?(e, not_)
        rescue *on_exceptions => e
          raise if on.is_a?(Hash) && !matches?(e, on)

          interval = intervals[index]
          on_retry.call(e, try, elapsed_time.call, interval) if on_retry
          raise if try >= tries || (elapsed_time.call + interval) > max_elapsed_time

          sleep interval if sleep_disabled != true
        end
      end
    end

    private

    def matches?(exception, exceptions)
      exception_list = exceptions.is_a?(Hash) ? exceptions.keys : exceptions
      exception_list.any? do |e|
        exception.is_a?(e) &&
          ([*exceptions[e]].empty? || [*exceptions[e]].any? { |pattern| exception.message =~ pattern })
      end
    end
  end
end
