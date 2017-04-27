module Retriable
  class Config
    def contexts
      @contexts ||= Contexts.new
    end

    def contexts=(envs)
      if envs.is_a?(Hash) && envs.values.all? { |e| e.is_a?(Hash) }
        envs.each { |env, options| contexts[env] = options }
      else
        raise ArgumentError, 'contexts must be a hash of hashes'
      end
    end

    class Contexts < Hash
      def []=(key, val)
        Retriable::Config.new(val) # Validate the options
        super(key, val)
      end
    end
    private_constant :Contexts
  end
end
