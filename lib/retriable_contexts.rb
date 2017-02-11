require 'retriable'
require 'retriable_contexts/config'

module Retriable
  def respond_to_missing?(method_sym, options = {}, &block)
    config.contexts.key?(method_sym) || super
  end

  def method_missing(method_sym, options = {}, &block)
    if config.contexts.key?(method_sym)
      Config.validate_options(config.contexts[method_sym])
      retriable(config.contexts[method_sym].merge(options), &block) if block
    else
      super
    end
  end
end
