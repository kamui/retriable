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
  end
end
