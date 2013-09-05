require 'retriable'

module Kernel
  include Retriable
  private :retriable
end
