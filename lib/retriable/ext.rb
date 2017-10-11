module Retriable
  module Ext
    # Retriable class extension
    #
    # @example
    #   extend Retriable::Ext
    #   def perform
    #     # some work
    #   end
    #   retriable :perform, on: Net::OpenTimeout
    #
    # @param method_name [Symbol,String] the method to wrap in a retryable call (should be defined on the class)
    # @param opts [Hash] options passed to Retriable#retriable
    def retriable(method_name, opts = {})
      prepend(Module.new { define_method(method_name) { |*a, &b| Retriable.retriable(opts) { super(*a, &b) } } })
    end
  end
end
