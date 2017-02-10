module Retriable
  class Context
    attr_accessor :options

    def initialize(options)
      raise ArgumentError, 'Context.new requires a hash' unless options.is_a?(Hash)

      options.each do |k, v|
        raise ArgumentError, "#{k} => #{v} is not a valid configuration" unless Config::PROPERTIES.include?(k)
      end

      @options = options
    end

    def retriable(&block)
      Retriable.retriable(@options, &block)
    end
  end
end
