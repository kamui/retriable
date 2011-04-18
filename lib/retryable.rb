module Retryable
  extend self
  
  def retryable(options = {})
    opts    = {:on => Exception, :times => 1}.merge(options)
    handler = {}
    
    retry_exception = opts[:on].is_a?(Array) ? opts[:on] : [opts[:on]]
    times = retries = opts[:times]
    attempts        = 0

    begin
      attempts += 1
      
      return yield(handler)
    rescue *retry_exception => exception
      opts[:then].call(exception, handler, attempts, retries, times) if opts[:then]
      
      if attempts <= times
        sleep(opts[:sleep] || (rand(11) / 100.0)) unless opts[:sleep] == false
        retries -= 1
        retry
      else
        opts[:finally].call(exception, handler, attempts, retries, times) if opts[:finally]
        raise exception
      end
    ensure
      opts[:always].call(handler, attempts, retries, times) if opts[:always]
    end

    yield(handler)
  end
end
