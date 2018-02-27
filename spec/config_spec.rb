require_relative "spec_helper"

describe Retriable::Config do
  let(:config) { described_class.new }

  context "defaults" do
    it "sleep defaults to enabled" do
      expect(config.sleep_disabled).to be_falsey
    end

    it "tries defaults to 3" do
      expect(config.tries).to eq(3)
    end

    it "max interval defaults to 60" do
      expect(config.max_interval).to eq(60)
    end

    it "randomization factor defaults to 0.5" do
      expect(config.base_interval).to eq(0.5)
    end

    it "multiplier defaults to 1.5" do
      expect(config.multiplier).to eq(1.5)
    end

    it "max elapsed time defaults to 900" do
      expect(config.max_elapsed_time).to eq(900)
    end

    it "intervals defaults to nil" do
      expect(config.intervals).to be_nil
    end

    it "timeout defaults to nil" do
      expect(config.timeout).to be_nil
    end

    it "on defaults to [StandardError]" do
      expect(config.on).to eq([StandardError])
    end

    it "on retry handler defaults to nil" do
      expect(config.on_retry).to be_nil
    end

    it "contexts defaults to {}" do
      expect(config.contexts).to eq({})
    end
  end

  it "raises errors on invalid configuration" do
    expect { described_class.new(does_not_exist: 123) }.to raise_error(ArgumentError)
  end
end
