module Retriable
  module_function

  def configure
    yield(config, context)
  end

  def context
    @context ||= {}
  end

  def with_context(key, options = {}, &block)
    raise ArgumentError, "Context #{key} is not found." if !context.key?(key)
    retriable(context[key].merge(options), &block) if block
  end
end
