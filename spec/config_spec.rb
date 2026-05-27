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

    it "timeout defaults to nil" do
      expect(default_config.timeout).to be_nil
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

    it "contexts defaults to {}" do
      expect(default_config.contexts).to eq({})
    end
  end

  it "raises errors on invalid configuration" do
    expect { described_class.new(does_not_exist: 123) }.to raise_error(ArgumentError, /not a valid option/)
  end

  it "raises errors on invalid timing configuration" do
    expect { described_class.new(rand_factor: 1.1) }.to raise_error(ArgumentError, /rand_factor/)
    expect { described_class.new(timeout: -1) }.to raise_error(ArgumentError, /timeout/)
  end

  context "timeout deprecation" do
    it "warns when timeout is configured" do
      expect do
        described_class.new(timeout: 5)
      end.to output(/timeout.*deprecated.*Retriable 4\.0/i).to_stderr
    end

    it "warns when timeout is set before validation" do
      config = described_class.new
      config.timeout = 5

      expect do
        config.validate!
      end.to output(/timeout.*deprecated.*Retriable 4\.0/i).to_stderr
    end

    it "does not warn when timeout is nil" do
      expect do
        described_class.new(timeout: nil)
      end.not_to output.to_stderr
    end

    it "does not warn when timeout is omitted" do
      expect do
        described_class.new
      end.not_to output.to_stderr
    end
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
end
