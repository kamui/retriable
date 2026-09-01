# frozen_string_literal: true

describe Retriable::Config do
  let(:default_config) { described_class.new }

  context "defaults" do
    it "sleep defaults to enabled" do
      expect(default_config.sleep_disabled).to be_falsey
    end

    it "tries defaults to 3" do
      expect(default_config.tries).to eq(3)
    end

    it "max interval defaults to 60" do
      expect(default_config.max_interval).to eq(60)
    end

    it "randomization factor defaults to 0.5" do
      expect(default_config.base_interval).to eq(0.5)
    end

    it "multiplier defaults to 1.5" do
      expect(default_config.multiplier).to eq(1.5)
    end

    it "max elapsed time defaults to 900" do
      expect(default_config.max_elapsed_time).to eq(900)
    end

    it "intervals defaults to nil" do
      expect(default_config.intervals).to be_nil
    end

    it "on defaults to [StandardError]" do
      expect(default_config.on).to eq([StandardError])
    end

    it "retry_if defaults to nil" do
      expect(default_config.retry_if).to be_nil
    end

    it "on_retry handler defaults to nil" do
      expect(default_config.on_retry).to be_nil
    end

    it "on_give_up handler defaults to nil" do
      expect(default_config.on_give_up).to be_nil
    end

    it "contexts defaults to {}" do
      expect(default_config.contexts).to eq({})
    end
  end

  it "raises errors on invalid configuration" do
    expect { described_class.new(does_not_exist: 123) }.to raise_error(ArgumentError, /not a valid option/)
  end

  it "rejects timeout as an unknown option" do
    expect { described_class.new(timeout: 5) }.to raise_error(ArgumentError, /not a valid option/)
  end

  it "raises errors on invalid timing configuration" do
    expect { described_class.new(rand_factor: 1.1) }.to raise_error(ArgumentError, /rand_factor/)
  end

  it "rejects randomized intervals whose runtime upper bound is infinite" do
    max_interval = Float("0x1.0d79435e50d79p+1023")

    expect { described_class.new(max_interval: max_interval, rand_factor: 0.9) }
      .to raise_error(ArgumentError, /finite randomized intervals/)
  end

  it "raises errors when intervals is not an array" do
    expect { described_class.new(intervals: "1") }.to raise_error(ArgumentError, /intervals must be an Array/)
  end

  it "requires a finite max_elapsed_time when tries is Float::INFINITY" do
    expect { described_class.new(tries: Float::INFINITY, max_elapsed_time: nil) }
      .to raise_error(ArgumentError, /max_elapsed_time must be a finite number/)
  end

  it "rejects intervals combined with tries: Float::INFINITY" do
    expect do
      described_class.new(
        tries: Float::INFINITY,
        max_elapsed_time: 60,
        intervals: [0.1, 0.2],
      )
    end.to raise_error(ArgumentError, /intervals cannot be used with tries: Float::INFINITY/)
  end

  it "accepts tries: Float::INFINITY with a finite max_elapsed_time" do
    expect { described_class.new(tries: Float::INFINITY, max_elapsed_time: 60) }
      .not_to raise_error
  end

  context "on: option validation" do
    it "accepts a single Exception subclass" do
      expect { described_class.new(on: StandardError) }.not_to raise_error
    end

    it "accepts Exception itself" do
      expect { described_class.new(on: Exception) }.not_to raise_error
    end

    it "accepts an array of Exception subclasses" do
      expect { described_class.new(on: [StandardError, RuntimeError]) }.not_to raise_error
    end

    it "accepts a Set of Exception subclasses" do
      expect { described_class.new(on: Set[StandardError, RuntimeError]) }.not_to raise_error
    end

    it "rejects a Set containing a non-Exception class" do
      expect { described_class.new(on: Set[StandardError, Kernel]) }
        .to raise_error(ArgumentError, /on must be an Exception class/)
    end

    it "accepts a hash with nil pattern values" do
      expect { described_class.new(on: { StandardError => nil }) }.not_to raise_error
    end

    it "accepts a hash with Regexp pattern values" do
      expect { described_class.new(on: { StandardError => /boom/ }) }.not_to raise_error
    end

    it "accepts a hash with Array-of-Regexp pattern values" do
      expect { described_class.new(on: { StandardError => [/a/, /b/] }) }.not_to raise_error
    end

    it "rejects Object as on:" do
      expect { described_class.new(on: Object) }
        .to raise_error(ArgumentError, /on must be an Exception class/)
    end

    it "rejects Kernel as on:" do
      expect { described_class.new(on: Kernel) }
        .to raise_error(ArgumentError, /on must be an Exception class/)
    end

    it "rejects an array containing a non-Exception class" do
      expect { described_class.new(on: [StandardError, Kernel]) }
        .to raise_error(ArgumentError, /on must be an Exception class/)
    end

    it "rejects a hash key that is not an Exception class" do
      expect { described_class.new(on: { Kernel => nil }) }
        .to raise_error(ArgumentError, /on must be an Exception class/)
    end

    it "rejects a hash value that is a String" do
      expect { described_class.new(on: { StandardError => "boom" }) }
        .to raise_error(ArgumentError, /on\[StandardError\] must be nil, a Regexp, or an Array of Regexps/)
    end

    it "rejects a hash value that is an Array containing a non-Regexp" do
      expect { described_class.new(on: { StandardError => [/a/, "b"] }) }
        .to raise_error(ArgumentError, /on\[StandardError\] must be nil, a Regexp, or an Array of Regexps/)
    end

    it "rejects a string passed as on:" do
      expect { described_class.new(on: "StandardError") }
        .to raise_error(ArgumentError, /on must be an Exception class/)
    end

    it "validates on: even when intervals is provided" do
      expect { described_class.new(intervals: [0.1], on: Object) }
        .to raise_error(ArgumentError, /on must be an Exception class/)
    end
  end

  context "callable option validation" do
    %i[retry_if on_retry on_give_up].each do |opt|
      it "accepts a callable for #{opt}" do
        expect { described_class.new(opt => ->(*) {}) }.not_to raise_error
      end

      it "accepts nil and false for #{opt}" do
        expect { described_class.new(opt => nil) }.not_to raise_error
        expect { described_class.new(opt => false) }.not_to raise_error
      end

      it "rejects a non-callable truthy value for #{opt}" do
        expect { described_class.new(opt => 5) }.to raise_error(ArgumentError, /#{opt}.*#call/)
      end
    end
  end

  context "context structure validation" do
    it "rejects a context whose options contain a nested :contexts key" do
      expect { described_class.new(contexts: { api: { contexts: {} } }) }
        .to raise_error(ArgumentError, /contexts is not a valid option/)
    end

    it "rejects a context with an unknown option key" do
      expect { described_class.new(contexts: { api: { does_not_exist: 1 } }) }
        .to raise_error(ArgumentError, /does_not_exist is not a valid option/)
    end

    it "validates context structure even when intervals is provided" do
      expect { described_class.new(intervals: [0.1], contexts: { api: { contexts: {} } }) }
        .to raise_error(ArgumentError, /contexts is not a valid option/)
    end

    it "accepts a non-Hash context value (treated as empty options)" do
      expect { described_class.new(contexts: { broken: nil }) }.not_to raise_error
    end

    it "accepts nil contexts" do
      expect { described_class.new(contexts: nil) }.not_to raise_error
    end

    it "accepts a valid context" do
      expect { described_class.new(contexts: { api: { tries: 3, base_interval: 1.0 } }) }.not_to raise_error
    end
  end

  context "#dup (copy-on-write isolation)" do
    it "deep-copies contexts so mutating the copy leaves the original intact" do
      original = described_class.new(contexts: { sql: { tries: 1 } })
      copy = original.dup

      copy.contexts[:http] = { tries: 2 }
      copy.contexts[:sql][:tries] = 99

      expect(original.contexts).to eq(sql: { tries: 1 })
    end

    it "deep-copies on and intervals collections" do
      original = described_class.new(on: [StandardError], intervals: [1, 2])
      copy = original.dup

      copy.on << ArgumentError
      copy.intervals << 3

      expect(original.on).to eq([StandardError])
      expect(original.intervals).to eq([1, 2])
    end

    it "preserves a non-collection on value (Exception class) without duping it" do
      original = described_class.new(on: StandardError)
      expect(original.dup.on).to be(StandardError)
    end

    it "deep-copies a Hash on value so the copy is a distinct hash" do
      original = described_class.new(on: { StandardError => /boom/ })
      copy = original.dup

      copy.on[ArgumentError] = /other/

      expect(original.on).to eq(StandardError => /boom/)
    end

    it "deep-copies mutable values nested inside a context's options" do
      original = described_class.new(contexts: { api: { intervals: [1, 2] } })
      copy = original.dup

      copy.contexts[:api][:intervals] << 3

      expect(original.contexts[:api][:intervals]).to eq([1, 2])
    end

    it "deep-copies the collection values of a Hash on" do
      original = described_class.new(on: { StandardError => [/boom/] })
      copy = original.dup

      copy.on[StandardError] << /bang/

      expect(original.on[StandardError]).to eq([/boom/])
    end

    it "preserves the container class of a Hash subclass" do
      subclass = Class.new(Hash)
      contexts = subclass.new
      contexts[:api] = { tries: 1 }

      expect(described_class.new(contexts: contexts).dup.contexts).to be_a(subclass)
    end

    it "preserves a contexts default_proc so absent keys still resolve" do
      contexts = Hash.new { |hash, key| hash[key] = { tries: 7 } }
      copy = described_class.new(contexts: contexts).dup

      expect(copy.contexts[:never_set]).to eq(tries: 7)
    end

    it "deep-copies a mutable Hash default" do
      fallback = []
      contexts = Hash.new(fallback)
      copy = described_class.new(contexts: contexts).dup

      copy.contexts.default << :copy_only

      expect(copy.contexts.default).not_to equal(fallback)
      expect(fallback).to be_empty
    end

    it "preserves a self-referential Hash default" do
      contexts = {}
      contexts.default = contexts
      copy = described_class.new(contexts: contexts).dup

      expect(copy.contexts.default).to equal(copy.contexts)
    end

    it "unfreezes copied containers so a configure block can mutate them" do
      original = described_class.new(contexts: { api: { tries: 1 } }.freeze)

      expect { original.dup.contexts[:added] = { tries: 2 } }.not_to raise_error
    end

    it "terminates on a self-referential contexts structure" do
      original = described_class.new
      original.contexts[:api] = { tries: 1 }
      original.contexts[:api][:cycle] = original.contexts

      copy = original.dup

      expect(copy.contexts).not_to equal(original.contexts)
      expect(copy.contexts[:api][:cycle]).to equal(copy.contexts)
    end
  end

  context "#freeze (published snapshot immutability)" do
    it "rejects mutation of the config itself" do
      config = described_class.new.freeze

      expect { config.tries = 99 }.to raise_error(FrozenError)
    end

    it "rejects mutation one level down, inside contexts" do
      config = described_class.new(contexts: { api: { tries: 1 } }).freeze

      expect { config.contexts[:api][:tries] = 99 }.to raise_error(FrozenError)
    end

    it "rejects mutation of the on collection" do
      config = described_class.new(on: [StandardError]).freeze

      expect { config.on << ArgumentError }.to raise_error(FrozenError)
    end

    it "freezes a mutable Hash default" do
      fallback = []
      contexts = Hash.new(fallback)
      contexts[:api] = { tries: 1 }
      config = described_class.new(contexts: contexts).freeze

      expect(config.contexts.default).to be_frozen
    end

    it "leaves leaves such as procs untouched" do
      handler = ->(_exception) { true }
      described_class.new(retry_if: handler).freeze

      expect(handler).not_to be_frozen
    end

    it "is idempotent" do
      config = described_class.new.freeze

      expect { config.freeze }.not_to raise_error
      expect(config.freeze).to equal(config)
    end
  end
end
