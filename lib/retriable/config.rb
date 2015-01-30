module Retriable
  class Config
    attr_accessor :sleep_disabled
    attr_accessor :tries
    attr_accessor :base_interval
    attr_accessor :max_interval
    attr_accessor :rand_factor
    attr_accessor :multiplier
    attr_accessor :max_elapsed_time
    attr_accessor :intervals
    attr_accessor :timeout
    attr_accessor :on
    attr_accessor :on_retry

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
  end
end
