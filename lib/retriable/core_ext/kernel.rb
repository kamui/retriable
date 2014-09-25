require 'retriable'

module Kernel
  def retriable(opts={}, &block)
    Retriable.retry(opts, &block)
  end
end
