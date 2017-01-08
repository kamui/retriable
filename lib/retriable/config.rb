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

    PROPERTIES.each { |p| attr_accessor p }
    attr_accessor :environments

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

    def validate_environments
      raise ArgumentError, ":environments must be a hash (#{@environments})" unless @environments.is_a?(Hash)
      raise ArgumentError, "Can't have an environment called 'retriable'" if @environments.keys.include?('retriable')

      @environments = Hash[
        @environments.map do |k, e|
          [k.to_sym, e.is_a?(Environment) ? e : Environment.new(e)]
        end
      ]
    end
  end
end
