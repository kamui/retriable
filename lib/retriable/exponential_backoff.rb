module Retriable
  class ExponentialBackoff
    attr_accessor :tries
    attr_accessor :base_interval
    attr_accessor :multiplier
    attr_accessor :max_interval
    attr_accessor :rand_factor

    def initialize(
      tries:            Retriable.config.tries,
      base_interval:    Retriable.config.base_interval,
      multiplier:       Retriable.config.multiplier,
      max_interval:     Retriable.config.max_interval,
      rand_factor:      Retriable.config.rand_factor
      )

      @tries          = tries
      @base_interval  = base_interval
      @multiplier     = multiplier
      @max_interval   = max_interval
      @rand_factor    = rand_factor
    end

    def intervals
      intervals = Array.new(tries) do |iteration|
        [base_interval * multiplier ** iteration, max_interval].min
      end

      return intervals if rand_factor == 0

      intervals.map { |i| randomize(i) }
    end

    protected
    def randomize(interval)
      return interval if rand_factor == 0
      delta = rand_factor * interval * 1.0
      min = interval - delta
      max = interval + delta
      rand(min..max)
    end
  end
end
