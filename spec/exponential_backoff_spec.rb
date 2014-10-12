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
    10000.times do |iteration|
      i = subject.new(tries: 9).intervals
      i[0].between?(0.25, 0.75).must_equal true
      i[1].between?(0.375, 1.125).must_equal true
      i[2].between?(0.5625, 1.6875).must_equal true
      i[3].between?(0.84375, 2.53125).must_equal true
      i[4].between?(1.265625, 3.796875).must_equal true
      i[5].between?(1.8984375, 5.6953125).must_equal true
      i[6].between?(2.84765625, 8.54296875).must_equal true
      i[7].between?(4.271484375, 12.814453125).must_equal true
      i[8].between?(6.4072265625, 19.2216796875).must_equal true
      i.size.must_equal 9
    end
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
