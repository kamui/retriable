# frozen_string_literal: true

module Retriable
  module Validation
    private

    def validate_positive_integer(name, value)
      return if value.is_a?(Integer) && value.positive?

      raise ArgumentError, "#{name} must be a positive integer"
    end

    def validate_non_negative_integer(name, value)
      return if value.is_a?(Integer) && value >= 0

      raise ArgumentError, "#{name} must be a non-negative integer"
    end

    def validate_non_negative_number(name, value)
      return if finite_number?(value) && value >= 0

      raise ArgumentError, "#{name} must be a non-negative number"
    end

    def validate_optional_non_negative_number(name, value)
      return if value.nil?

      validate_non_negative_number(name, value)
    end

    def validate_rand_factor
      return if finite_number?(rand_factor) && rand_factor >= 0 && rand_factor <= 1

      raise ArgumentError, "rand_factor must be between 0 and 1"
    end

    def finite_number?(value)
      value.is_a?(Numeric) && value.to_f.finite?
    end

    def unbounded_tries?(value)
      value.is_a?(Numeric) && value.respond_to?(:infinite?) && value.infinite? == 1
    end

    module_function :unbounded_tries?

    # Validates an `on:` value. Acceptable shapes:
    #   - a Class that descends from Exception
    #   - an Array whose elements are Classes that descend from Exception
    #   - a Hash whose keys are such Classes and whose values are nil,
    #     a Regexp, or an Array of Regexps
    #
    # Without this validation, callers can pass values like `Object` or
    # `Kernel` and silently retry process-critical exceptions such as
    # SystemExit and Interrupt, because every Exception's ancestor chain
    # includes both. Hash values that are not Regexps (e.g. plain Strings)
    # also silently fail to match in #hash_exception_match?, so we require
    # Regexp values explicitly.
    def validate_on(value)
      case value
      when Hash
        value.each do |klass, pattern|
          validate_on_class(klass)
          validate_on_hash_value(klass, pattern)
        end
      when Array
        value.each { |klass| validate_on_class(klass) }
      else
        validate_on_class(value)
      end
    end

    def validate_on_class(klass)
      return if klass.is_a?(Class) && klass <= Exception

      raise ArgumentError, "on must be an Exception class or a collection of Exception classes, got #{klass.inspect}"
    end

    def validate_on_hash_value(klass, pattern)
      return if pattern.nil?
      return if pattern.is_a?(Regexp)
      return if pattern.is_a?(Array) && pattern.all?(Regexp)

      raise ArgumentError,
            "on[#{klass}] must be nil, a Regexp, or an Array of Regexps, got #{pattern.inspect}"
    end
  end
end
