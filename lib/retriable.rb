require 'timeout'
require 'retriable/exponential_backoff'
require 'retriable/config'
require 'retriable/version'

module Retriable
  module_function

  def configure
    yield(config)
    config.validate!
  end

  def config
    @config ||= Config.new
  end

  def reset!
    @config = Config.new
  end

  def retriable(opts = {}, &block)
    raise ArgumentError, 'retriable options must be a hash' unless opts && opts.is_a?(Hash)
    config.dup.retriable(opts, &block)
  end
end
