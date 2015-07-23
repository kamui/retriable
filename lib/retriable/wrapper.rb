class Retriable::Wrapper
  def initialize(with_object, retriable_options)
    @o = with_object
    @retriable_options = retriable_options
  end
  
  def respond_to_missing?(*a)
    @o.respond_to?(*a)
  end
  
  def method_missing(*a)
    if block_given?
      __retrying { @o.public_send(*a){|*ba| yield(*ba)} }
    else
      __retrying { @o.public_send(*a) }
    end
  end
  
  private
  
  # Executes a block within Retriable setup with @retriable_options
  def __retrying
    Retriable.retriable(@retriable_options) { yield }
  end
end
