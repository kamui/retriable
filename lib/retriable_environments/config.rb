module Retriable
  class Config
    def environments
      @environments ||= {}
    end

    def environments=(envs)
      if envs.is_a?(Hash) && envs.values.all? { |e| e.is_a? Hash }
        @environments = envs
      else
        raise ArgumentError, 'environments must be a hash of hashes'
      end
    end
  end
end
