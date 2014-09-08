require 'timeout'

module Retriable
  class Retry
    attr_accessor :tries
    attr_accessor :interval
    attr_accessor :timeout
    attr_accessor :on
    attr_accessor :on_retry

    def initialize
      yield self if block_given?

      @on       ||= [StandardError, Timeout::Error]
      @tries    ||= interval.is_a?(Enumerable) ? interval.count : 3
      @interval ||= 0
    end

    def perform(&block)
      count = 0

      begin
        if @timeout
          Timeout::timeout(@timeout) { yield }
        else
          yield
        end
      rescue *[*on] => exception
        raise if count >= @tries
        count += 1

        @on_retry.call(exception, count) if @on_retry
        sleep sleep_for(count)

        retry
      end
    end

  private

    # @param try [Integer] current try number (1..)
    # @return [Numeric]
    def sleep_for(try)
      if @interval.respond_to?(:call)
        @interval.call(try)
      elsif @interval.is_a?(Enumerable)
        # because we start from the first try
        @interval[(try - 1) % @interval.count]
      else
        @interval
      end
    end
  end
end
