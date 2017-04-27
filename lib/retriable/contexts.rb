require 'retriable/contexts/config'

module Retriable
  module_function

  def respond_to_missing?(method_sym, options = {}, &block)
    config.contexts.key?(method_sym) || super
  end

  def method_missing(method_sym, options = {}, &block)
    if (context = config.contexts[method_sym])
      Config.new(context).retriable(options, &block) if block
    else
      super
    end
  end
end
