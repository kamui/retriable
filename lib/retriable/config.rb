# frozen_string_literal: true

require_relative "exponential_backoff"
require_relative "validation"

module Retriable
  class Config
    include Validation

    ATTRIBUTES = (ExponentialBackoff::ATTRIBUTES + %i[
      sleep_disabled
      max_elapsed_time
      intervals
      on
      retry_if
      on_retry
      on_give_up
      contexts
    ]).freeze

    CONTEXT_ATTRIBUTES = (ATTRIBUTES - %i[contexts]).freeze
    private_constant :CONTEXT_ATTRIBUTES

    OWNED_CONTAINER_ATTRIBUTES = %i[on intervals contexts].freeze
    private_constant :OWNED_CONTAINER_ATTRIBUTES

    attr_accessor(*ATTRIBUTES)

    def initialize(opts = {})
      defaults = ExponentialBackoff::DEFAULTS

      @tries            = defaults[:tries]
      @base_interval    = defaults[:base_interval]
      @max_interval     = defaults[:max_interval]
      @rand_factor      = defaults[:rand_factor]
      @multiplier       = defaults[:multiplier]
      @sleep_disabled   = false
      @max_elapsed_time = 900 # 15 min
      @intervals        = nil
      @on               = [StandardError]
      @retry_if         = nil
      @on_retry         = nil
      @on_give_up       = nil
      @contexts         = {}

      opts.each do |k, v|
        raise ArgumentError, "#{k} is not a valid option" if !ATTRIBUTES.include?(k)

        instance_variable_set(:"@#{k}", v)
      end

      validate!
    end

    def to_h
      ATTRIBUTES.to_h { |key| [key, public_send(key)] }
    end

    def validate!
      validate_contexts
      validate_callable(:retry_if, retry_if)
      validate_callable(:on_retry, on_retry)
      validate_callable(:on_give_up, on_give_up)
      validate_on(on)
      validate_intervals
      if unbounded_tries?(tries)
        validate_unbounded_tries
      else
        validate_optional_non_negative_number(:max_elapsed_time, max_elapsed_time)
        return if intervals

        validate_positive_integer(:tries, tries)
      end

      validate_backoff_options
    end

    # Deep-freezes the containers this Config owns, then itself. Without the deep
    # part a "frozen" Config stays mutable one level down
    # (`config.contexts[:api][:tries] = 1`), which is precisely the corruption a
    # published snapshot exists to rule out. Leaves — procs, exception classes,
    # regexps, scalars — are shared by reference and left untouched.
    #
    # Retriable only ever freezes a #dup it produced itself, so this never
    # freezes a container the caller still holds.
    def freeze
      return self if frozen?

      OWNED_CONTAINER_ATTRIBUTES.each do |attribute|
        deep_freeze(instance_variable_get(:"@#{attribute}"))
      end
      super
    end

    private

    def validate_contexts
      return unless contexts.is_a?(Hash)
      return if contexts.empty?

      contexts.each_value do |options|
        next unless options.is_a?(Hash)

        options.each_key do |k|
          next if CONTEXT_ATTRIBUTES.include?(k)

          raise ArgumentError, "#{k} is not a valid option"
        end
      end
    end

    def initialize_copy(other)
      super
      OWNED_CONTAINER_ATTRIBUTES.each do |attribute|
        instance_variable_set(:"@#{attribute}", deep_dup(other.public_send(attribute)))
      end
    end

    # Recursively copies the mutable containers (Hash/Array/Set) so a dup is fully
    # isolated from the original, leaving leaves (scalars, procs, exception
    # classes, regexps) shared by reference.
    #
    # Copies start from #dup rather than a fresh literal. Rebuilding into a bare
    # `{}` silently downgrades a Hash subclass to Hash and drops its
    # default/default_proc, so a `contexts` hash with indifferent access would
    # stop resolving string keys after the first #configure.
    #
    # Frozen state is deliberately not carried over: a dup is the mutable working
    # copy that a #configure block mutates, and Retriable re-freezes it on
    # publish.
    #
    # `seen` maps each source container to its copy so a self-referential
    # structure terminates instead of recursing until the stack blows.
    def deep_dup(value, seen = {}.compare_by_identity)
      case value
      when Hash, Array, Set
        return seen[value] if seen.key?(value)

        copy = value.dup
        seen[value] = copy
        deep_dup_into(value, copy, seen)
        copy
      else value
      end
    end

    def deep_dup_into(value, copy, seen)
      case value
      when Hash then deep_dup_hash(value, copy, seen)
      when Array then value.each_with_index { |val, index| copy[index] = deep_dup(val, seen) }
      when Set then copy.replace(value.map { |val| deep_dup(val, seen) })
      end
    end

    # Keys are deliberately left alone. Ruby already dups and freezes an unfrozen
    # String key on assignment, and the supported key types (Symbols for
    # `contexts`, exception classes for `on`) are immutable already.
    #
    # A mutable default value is part of the copied graph, because a shared one
    # would let `config.contexts[:absent] << x` mutate the caller's object. A
    # default_proc stays shared: it is a callable leaf, like every other proc a
    # Config holds.
    def deep_dup_hash(value, copy, seen)
      value.each { |key, val| copy[key] = deep_dup(val, seen) }
      copy.default = deep_dup(value.default, seen) unless value.default_proc
    end

    # Freezes exactly what #deep_dup treats as a container, so the two agree on
    # where a Config's mutable surface ends. `seen` guards the same
    # self-referential case.
    def deep_freeze(value, seen = {}.compare_by_identity)
      case value
      when Hash then deep_freeze_hash(value, seen)
      when Array, Set then deep_freeze_collection(value, seen)
      else value
      end
    end

    def deep_freeze_hash(value, seen)
      return value if seen[value]

      seen[value] = true
      value.each_value { |val| deep_freeze(val, seen) }
      deep_freeze(value.default, seen) unless value.default_proc
      value.freeze
    end

    def deep_freeze_collection(value, seen)
      return value if seen[value]

      seen[value] = true
      value.each { |val| deep_freeze(val, seen) }
      value.freeze
    end

    def validate_backoff_options
      validate_non_negative_number(:base_interval, base_interval)
      validate_non_negative_number(:multiplier, multiplier)
      validate_non_negative_number(:max_interval, max_interval)
      validate_rand_factor
    end

    def validate_unbounded_tries
      if intervals
        raise ArgumentError,
              "intervals cannot be used with tries: Float::INFINITY"
      end

      unless finite_number?(max_elapsed_time)
        raise ArgumentError,
              "max_elapsed_time must be a finite number when tries is Float::INFINITY"
      end

      validate_non_negative_number(:max_elapsed_time, max_elapsed_time)
    end

    def validate_intervals
      return if intervals.nil?
      raise ArgumentError, "intervals must be an Array" unless intervals.is_a?(Array)
      return if intervals.all? { |interval| finite_number?(interval) && interval >= 0 }

      raise ArgumentError, "intervals must contain only non-negative numbers"
    end
  end
end
