module Retriable
  class ExponentialBackoff
    attr_accessor :max_tries, :base_interval, :multiplier, :max_interval, :rand_factor

    def initialize(
      max_tries: Retriable.config.max_tries,
      base_interval: Retriable.config.base_interval,
      multiplier: Retriable.config.multiplier,
      max_interval: Retriable.config.max_interval,
      rand_factor: Retriable.config.rand_factor
      )

      @max_tries = max_tries
      @base_interval = base_interval
      @multiplier = multiplier
      @max_interval = max_interval
      @rand_factor = rand_factor
    end

    def intervals
      intervals = Array.new(max_tries) do |iteration|
        [base_interval * multiplier ** iteration, max_interval].min
      end

      return intervals if rand_factor == 0

      intervals.map { |i| randomize(i) }
    end

    protected
    def randomize(interval)
      return interval if rand_factor == 0
      delta = rand_factor * interval * 1.0
      min_interval = interval - delta
      max_interval = interval + delta
      rand(min_interval..max_interval)
    end
  end
end
