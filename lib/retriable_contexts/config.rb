module Retriable
  class Config
    def self.validate_options(options)
      raise ArgumentError, 'Context must be a hash' unless options.is_a?(Hash)

      options.each do |k, v|
        raise ArgumentError, "#{k} => #{v} is not a valid configuration" unless PROPERTIES.include?(k)
      end
    end

    def contexts
      @contexts ||= {}
    end

    def contexts=(envs)
      if envs.is_a?(Hash) && envs.values.all? { |e| e.is_a?(Hash) && Config.validate_options(e) }
        @contexts = envs
      else
        raise ArgumentError, 'contexts must be a hash of hashes'
      end
    end
  end
end
