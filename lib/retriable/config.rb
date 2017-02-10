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

    def validate!
      if @on.is_a?(Array)
        raise ArgumentError, invalid_config_message(:on) unless @on.all? { |e| e.is_a?(Class) }
      elsif @on.is_a?(Hash)
        @on.each do |k, v|
          next if v.nil? || v.is_a?(Regexp)
          raise ArgumentError, invalid_config_message(:on) unless v.is_a?(Array) && v.all? { |rgx| rgx.is_a?(Regexp) }
        end
      else
        raise ArgumentError, invalid_config_message(:on)
      end
    end

    private

    def invalid_config_message(param)
      "Invalid configuration of #{param}: #{public_send(param)}"
    end
  end
end
