module Retriable
  class Config
    def contexts
      @contexts ||= {}
    end

    def contexts=(envs)
      if envs.is_a?(Hash) && envs.values.all? { |e| e.is_a?(Hash) }
        envs.each { |_, options| c = self.class.new(options).validate! }
        @contexts = envs
      else
        raise ArgumentError, 'contexts must be a hash of hashes'
      end
    end
  end
end
