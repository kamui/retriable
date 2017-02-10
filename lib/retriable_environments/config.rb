module Retriable
  class Config
    def environments
      @environments ||= {}
    end

    private

    def validate_environments!
      raise ArgumentError, ":environments must be a hash (#{@environments})" unless @environments.is_a?(Hash)

      @environments = Hash[
        @environments.map do |k, e|
          [k.to_sym, e.is_a?(Environment) ? e : Environment.new(e)]
        end
      ]

      unless (overloaded_methods = (@environments.keys & Retriable.methods)).empty?
        raise ArgumentError, "Can't use method names #{overloaded_methods.join(',')} as environment keys"
      end
    end
  end
end
