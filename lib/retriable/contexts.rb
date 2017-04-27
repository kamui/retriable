require 'retriable/contexts/config'

module Retriable
  module_function

  def respond_to_missing?(method_sym, options = {}, &block)
    config.contexts.key?(method_sym) || super
  end

  def method_missing(method_sym, options = {}, &block)
    if (context = config.contexts[method_sym])
      raise ArgumentError, 'Options to an environment call must be a hash' unless options.is_a?(Hash)
      retriable(context.merge(options), &block) if block
    else
      super
    end
  end
end
