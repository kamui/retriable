module Retriable
  class Config
    def contexts
      @contexts ||= {}
    end

    def contexts=(envs)
      if envs.is_a?(Hash) && envs.values.all? { |e| e.is_a?(Hash) && Context.validate(e) }
        @contexts = envs
      else
        raise ArgumentError, 'contexts must be a hash of hashes'
      end
    end
  end
end
