module Retriable
  class ExponentialBackoff
    ATTRIBUTES = %i[
tries
base_interval
multiplier
max_interval
rand_factor
].freeze

    attr_accessor(*ATTRIBUTES)

    def initialize(opts = {})
      @tries         = 3
      @base_interval = 0.5
      @max_interval  = 60
      @rand_factor   = 0.5
      @multiplier    = 1.5

      opts.each do |k, v|
        raise ArgumentError, "#{k} is not a valid option" if !ATTRIBUTES.include?(k)
        instance_variable_set(:"@#{k}", v)
      end
    end

    def intervals
      Enumerator.new(tries) do |result|
        try = 0
        loop do
          interval = [base_interval * multiplier**try, max_interval].min
          result << randomize(interval)
          try += 1
          raise StopIteration if tries && try >= tries
        end
      end.lazy
    end

    private

    def randomize(interval)
      return interval if rand_factor.zero?

      delta = rand_factor * interval * 1.0
      min = interval - delta
      max = interval + delta
      rand(min..max)
    end
  end
end
