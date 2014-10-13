require_relative "spec_helper"

describe Retriable::ExponentialBackoff do
  subject do
    Retriable::ExponentialBackoff
  end

  before do
    srand 0
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

  it "generates 10 randomized intervals" do
    subject.new(tries: 9).intervals.must_equal([
      0.5244067512211441,
      0.9113920238761231,
      1.2406087918999114,
      1.7632403621664823,
      2.338001204738311,
      4.350816718580626,
      5.339852157217869,
      11.889873261212443,
      18.756037881636484
    ])
  end

  it "generates defined number of intervals" do
    subject.new(tries: 5).intervals.size.must_equal 5
  end

  it "generates intervals with a defined base interval" do
    subject.new(base_interval: 1).intervals.must_equal([
      1.0488135024422882,
      1.8227840477522461,
      2.4812175837998227
    ])
  end

  it "generates 10 non-randomized intervals" do
    subject.new(
      tries: 10,
      rand_factor: 0.0
    ).intervals.must_equal([
      0.5,
      0.75,
      1.125,
      1.6875,
      2.53125,
      3.796875,
      5.6953125,
      8.54296875,
      12.814453125,
      19.2216796875
    ])
  end
end
