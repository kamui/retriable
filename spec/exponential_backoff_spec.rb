require_relative "spec_helper"

describe Retriable::ExponentialBackoff do
  subject do
    Retriable::ExponentialBackoff
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

  it "generates randomized intervals" do
    i = subject.new(tries: 9).intervals
    i[0].between?(0.25, 0.75).must_equal true
    i[1].between?(0.375, 1.125).must_equal true
    i[2].between?(0.562, 1.687).must_equal true
    i[3].between?(0.8435, 2.53).must_equal true
    i[4].between?(1.265, 3.795).must_equal true
    i[5].between?(1.897, 5.692).must_equal true
    i[6].between?(2.846, 8.538).must_equal true
    i[7].between?(4.269, 12.807).must_equal true
    i[8].between?(6.403, 19.210).must_equal true
  end

  it "generates 5 non-randomized intervals" do
    subject.new(
      tries: 5,
      rand_factor: 0.0
    ).intervals.must_equal([
      0.5,
      0.75,
      1.125,
      1.6875,
      2.53125
    ])
  end
end
