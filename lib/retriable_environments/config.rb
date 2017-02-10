module Retriable
  class Config
    def environments
      @environments ||= {}
    end

    def environments=(environments_hash)
      raise ArgumentError, 'environments must be a hash' unless environments_hash.is_a?(Hash)
      @environments = environments_hash
    end
  end
end
