require 'retriable'
require 'retriable_environments/config.rb'
require 'retriable_environments/environment'

module Retriable
  def respond_to_missing?(method_sym, options = {}, &block)
    config.environments.key?(method_sym) || super
  end

  def method_missing(method_sym, options = {}, &block)
    if config.environments.key?(method_sym)
      Environment.new(config.environments[method_sym].merge(options)).retriable(&block) if block
    else
      super
    end
  end
end
