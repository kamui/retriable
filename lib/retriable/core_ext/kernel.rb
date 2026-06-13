# frozen_string_literal: true

require_relative "../../retriable"

module Kernel
  def retriable(opts = {}, &)
    Retriable.retriable(opts, &)
  end

  def retriable_with_context(context_key, opts = {}, &)
    Retriable.with_context(context_key, opts, &)
  end

  private :retriable, :retriable_with_context
end
