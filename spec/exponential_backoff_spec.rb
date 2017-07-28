require_relative "spec_helper"

describe Retriable::ExponentialBackoff do
  subject do
    Retriable::ExponentialBackoff
  end

  before do
    srand 0
  end

  it "tries defaults to 3" do
    expect(subject.new.tries).must_equal 3
  end

  it "max interval defaults to 60" do
    expect(subject.new.max_interval).must_equal 60
  end

  it "randomization factor defaults to 0.5" do
    expect(subject.new.base_interval).must_equal 0.5
  end

  it "multiplier defaults to 1.5" do
    expect(subject.new.multiplier).must_equal 1.5
  end

  it "generates 10 randomized intervals" do
    expect(subject.new(tries: 9).intervals.map { |x| x.round(3) }).must_equal(
      [0.524, 0.911, 1.241, 1.763, 2.338, 4.351, 5.34, 11.89, 18.756]
    )
  end

  it "generates defined number of intervals" do
    expect(subject.new(tries: 5).intervals.size).must_equal 5
  end

  it "generates intervals with a defined base interval" do
    expect(subject.new(base_interval: 1).intervals.map { |x| x.round(3) }).must_equal([1.049, 1.823, 2.481])
  end

  it "generates intervals with a defined multiplier" do
    expect(subject.new(multiplier: 1).intervals.map { |x| x.round(3) }).must_equal([0.524, 0.608, 0.551])
  end

  it "generates intervals with a defined max interval" do
    expect(subject.new(max_interval: 1.0, rand_factor: 0.0).intervals).must_equal([0.5, 0.75, 1.0])
  end

  it "generates intervals with a defined rand_factor" do
    expect(subject.new(rand_factor: 0.2).intervals.map { |x| x.round(3) }).must_equal([0.51, 0.815, 1.171])
  end

  it "generates 10 non-randomized intervals" do
    expect(subject.new(
      tries: 10,
      rand_factor: 0.0,
    ).intervals).must_equal([
      0.5,
      0.75,
      1.125,
      1.6875,
      2.53125,
      3.796875,
      5.6953125,
      8.54296875,
      12.814453125,
      19.2216796875,
    ])
  end
end
