require 'retriable'
require 'retriable_contexts/config.rb'
require 'retriable_contexts/context'

module Retriable
  def respond_to_missing?(method_sym, options = {}, &block)
    config.contexts.key?(method_sym) || super
  end

  def method_missing(method_sym, options = {}, &block)
    if config.contexts.key?(method_sym)
      Context.new(config.contexts[method_sym].merge(options)).retriable(&block) if block
    else
      super
    end
  end
end
