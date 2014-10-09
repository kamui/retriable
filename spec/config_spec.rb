require_relative "spec_helper"

describe Retriable::Config do
  subject do
    Retriable::Config
  end

  it "sleep defaults to enabled" do
    subject.new.sleep_disabled.must_equal false
  end

  it "tries defaults to 3" do
    subject.new.tries.must_equal 3
  end

  it "max interval defaults to 60" do
    subject.new.max_interval.must_equal 60
  end

  it "randomization factor defaults to 0.5" do
    subject.new.base_interval.must_equal 0.5
  end

  it "multiplier defaults to 1.5" do
    subject.new.multiplier.must_equal 1.5
  end

  it "max elapsed time defaults to 900" do
    subject.new.max_elapsed_time.must_equal 900
  end

  it "intervals defaults to nil" do
    subject.new.intervals.must_be_nil
  end

  it "timeout defaults to nil" do
    subject.new.timeout.must_be_nil
  end

  it "on defaults to [StandardError]" do
    subject.new.on.must_equal [StandardError]
  end

  it "on retry handler defaults to nil" do
    subject.new.on_retry.must_be_nil
  end
end
