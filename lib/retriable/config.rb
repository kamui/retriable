module Retriable
  class Config
    PROPERTIES = [
      :sleep_disabled,
      :tries,
      :base_interval,
      :max_interval,
      :rand_factor,
      :multiplier,
      :max_elapsed_time,
      :intervals,
      :timeout,
      :on,
      :on_retry
    ]

    attr_accessor :environments
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
      @environments      = {}
    end

    def validate!
      validate_environments!

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

    def validate_environments!
      raise ArgumentError, ":environments must be a hash (#{@environments})" unless @environments.is_a?(Hash)

      @environments = Hash[
        @environments.map do |k, e|
          [k.to_sym, e.is_a?(Environment) ? e : Environment.new(e)]
        end
      ]

      unless (overloaded_methods = (@environments.keys & Retriable.methods)).empty?
        raise ArgumentError, "Can't use method names #{overloaded_methods.join(',')} as environment keys"
      end
    end

    def invalid_config_message(param)
      "Invalid configuration of #{param}: #{public_send(param)}"
    end
  end
end
