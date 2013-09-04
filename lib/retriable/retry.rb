require 'timeout'

module Retriable
  class Retry
    attr_accessor :tries
    attr_accessor :interval
    attr_accessor :timeout
    attr_accessor :on
    attr_accessor :on_retry

    def initialize
      @tries      = 3
      @interval   = 0
      @timeout    = nil
      @on         = [StandardError, Timeout::Error]
      @on_retry   = nil

      yield self if block_given?
    end

    def perform
      count = 0
      begin
        if @timeout
          Timeout::timeout(@timeout) { yield }
        else
          yield
        end
      rescue *[*on] => exception
        @tries -= 1
        if @tries > 0
          count += 1
          @on_retry.call(exception, count) if @on_retry
          sleep_for = @interval.respond_to?(:call) ? @interval.call(count) : @interval
          sleep sleep_for if sleep_for > 0

          retry
        else
          raise
        end
      end
    end
  end
end
