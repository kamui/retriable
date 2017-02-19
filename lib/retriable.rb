require 'timeout'
require_relative File.join('retriable', 'exponential_backoff')
require_relative File.join('retriable', 'config')
require_relative File.join('retriable', 'version')

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
