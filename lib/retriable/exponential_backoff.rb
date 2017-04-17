module Retriable
  class ExponentialBackoff
    PROPERTIES = [
      :base_interval,
      :max_interval,
      :multiplier,
      :rand_factor,
      :tries
    ].freeze

    PROPERTIES.each { |p| attr_accessor p }

    def initialize(opts = {})
      PROPERTIES.each { |p| public_send("#{p}=", opts[p] || Retriable.config.public_send(p)) }
    end

    def intervals
      intervals = Array.new(tries) do |iteration|
        [base_interval * multiplier**iteration, max_interval].min
      end

      return intervals if rand_factor.zero?

      intervals.map { |i| randomize(i) }
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
