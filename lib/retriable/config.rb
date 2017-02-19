module Retriable
  class Config
    PROPERTIES = [
      :base_interval,
      :intervals,
      :max_elapsed_time,
      :max_interval,
      :multiplier,
      :on,
      :on_retry,
      :rand_factor,
      :sleep_disabled,
      :timeout,
      :tries
    ]

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
        raise ArgumentError, "#{k} => #{v} is not a valid configuration" unless PROPERTIES.include?(k)
      end

      PROPERTIES.each do |property|
        public_send("#{property}=", opts[property] || public_send(property))
      end

      validate!

      start_time = Time.now
      elapsed_time = -> { Time.now - start_time }

      if intervals
        @tries = intervals.size + 1
      else
        @intervals = ExponentialBackoff.new(
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
          sleep(interval) if sleep_disabled != true
        end
      end
    end

    def validate!
      if on.is_a?(Array)
        raise ArgumentError, invalid_config_message(:on) unless on.all? { |e| e < Exception }
      elsif on.is_a?(Hash)
        on.each do |k, v|
          raise ArgumentError, "'#{k}' is not an Exception" unless k < Exception
          next if v.nil? || v.is_a?(Regexp)
          raise ArgumentError, invalid_config_message(:on) unless v.is_a?(Array) && v.all? { |rgx| rgx.is_a?(Regexp) }
        end
      elsif !(on < Exception)
        raise ArgumentError, invalid_config_message(:on)
      end

      if intervals && !intervals.is_a?(Array)
        raise ArgumentError, invalid_config_message(:intervals)
      end
    end

    private

    def invalid_config_message(param)
      "Invalid configuration of #{param}: #{public_send(param)}"
    end
  end
end
