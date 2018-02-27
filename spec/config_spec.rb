require_relative "spec_helper"

describe Retriable::Config do
  it "sleep defaults to enabled" do
    expect(described_class.new.sleep_disabled).to be_falsey
  end

  it "tries defaults to 3" do
    expect(described_class.new.tries).to eq(3)
  end

  it "max interval defaults to 60" do
    expect(described_class.new.max_interval).to eq(60)
  end

  it "randomization factor defaults to 0.5" do
    expect(described_class.new.base_interval).to eq(0.5)
  end

  it "multiplier defaults to 1.5" do
    expect(described_class.new.multiplier).to eq(1.5)
  end

  it "max elapsed time defaults to 900" do
    expect(described_class.new.max_elapsed_time).to eq(900)
  end

  it "intervals defaults to nil" do
    expect(described_class.new.intervals).to be_nil
  end

  it "timeout defaults to nil" do
    expect(described_class.new.timeout).to be_nil
  end

  it "on defaults to [StandardError]" do
    expect(described_class.new.on).to eq([StandardError])
  end

  it "on retry handler defaults to nil" do
    expect(described_class.new.on_retry).to be_nil
  end

  it "contexts defaults to {}" do
    expect(described_class.new.contexts).to eq(Hash.new)
  end

  it "raises errors on invalid configuration" do
    expect { described_class.new(does_not_exist: 123) }.to raise_error(ArgumentError)
  end
end
