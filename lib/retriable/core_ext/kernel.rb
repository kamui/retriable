require 'retriable'

module Kernel
  include Retriable::DSL
  private :retriable
end
