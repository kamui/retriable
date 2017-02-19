module Retriable
  class Config
    EXPONENTIAL_BACKOFF_PROPERTIES = [
      :base_interval,
      :max_interval,
      :multiplier,
      :rand_factor,
      :tries
    ].freeze

    NUMERIC_PROPERTIES = EXPONENTIAL_BACKOFF_PROPERTIES + [
      :max_elapsed_time,
      :timeout,
      :tries
    ].freeze

    PROPERTIES = NUMERIC_PROPERTIES + [
      :intervals,
      :on,
      :on_retry,
      :sleep_disabled
    ].freeze

    PROPERTIES.each { |p| attr_accessor p }

    def initialize
      @sleep_disabled    = false
      @tries             = 3
      @base_interval     = 0.5
      @max_interval      = 60
      @rand_factor       = 0.5
      @multiplier        = 1.5
      @max_elapsed_time  = 900 # 15 min
      @intervals         = nil
      @timeout           = nil
      @on                = [StandardError]
      @on_retry          = nil
    end

    def retriable(opts = {})
      opts.each do |k, v|
        raise ArgumentError, "#{k} => #{v} is not a valid option" unless PROPERTIES.include?(k)
        public_send("#{k}=", v) if v
      end

      validate!
      start_time = Time.now
      elapsed_time = -> { Time.now - start_time }
      exception_list = on.is_a?(Hash) ? on.keys : on

      if intervals
        @tries = intervals.size + 1
      else
        @intervals = ExponentialBackoff.new(backoff_options).intervals
      end

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
          sleep(interval) if sleep_disabled != true
        end
      end
    end

    def validate!
      if on.is_a?(Array)
        raise_invalid_config_message(:on) unless on.all? { |e| valid_exception?(e) }
      elsif on.is_a?(Hash)
        on.each do |k, v|
          raise ArgumentError, "'#{k}' is not an Exception" unless valid_exception?(k)
          next if v.nil? || v.is_a?(Regexp)
          raise_invalid_config_message(:on) unless v.is_a?(Array) && v.all? { |rgx| rgx.is_a?(Regexp) }
        end
      elsif !valid_exception?(on)
        raise_invalid_config_message(:on)
      end

      if intervals && !intervals.is_a?(Array)
        raise_invalid_config_message(:intervals)
      end

      NUMERIC_PROPERTIES.each do |option|
        raise_invalid_config_message(option) if public_send(option) && !public_send(option).is_a?(Numeric)
      end

      raise_invalid_config_message(:on_retry) if on_retry && !on_retry.is_a?(Proc)
    end

    private

    def raise_invalid_config_message(param)
      raise ArgumentError, "Invalid configuration of #{param}: #{public_send(param)}"
    end

    def valid_exception?(e)
      e.is_a?(Class) && e < Exception
    end

    def backoff_options
      hash = EXPONENTIAL_BACKOFF_PROPERTIES.inject({}) { |hsh, prop| hsh.merge(prop => public_send(prop)) }
      hash[:tries] -= 1 if hash[:tries]
      hash
    end
  end
end
