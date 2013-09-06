require 'retriable/retry'

module Retriable
  extend self

  def retriable(opts = {}, &block)
    raise LocalJumpError unless block_given?

    Retry.new do |r|
      r.tries    = opts[:tries] if opts[:tries]
      r.on       = opts[:on] if opts[:on]
      r.interval = opts[:interval] if opts[:interval]
      r.timeout  = opts[:timeout] if opts[:timeout]
      r.on_retry = opts[:on_retry] if opts[:on_retry]
    end.perform(&block)
  end
end
