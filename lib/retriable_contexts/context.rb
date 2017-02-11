module Retriable
  class Context
    def self.validate(options)
      raise ArgumentError, 'Context must be a hash' unless options.is_a?(Hash)

      options.each do |k, v|
        raise ArgumentError, "#{k} => #{v} is not a valid configuration" unless Config::PROPERTIES.include?(k)
      end
    end
  end
end
