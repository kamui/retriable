describe Retriable::ExponentialBackoff do
  context "defaults" do
    let(:backoff_config) { described_class.new }

    it "tries defaults to 3" do
      expect(backoff_config.tries).to eq(3)
    end

    it "max interval defaults to 60" do
      expect(backoff_config.max_interval).to eq(60)
    end

    it "randomization factor defaults to 0.5" do
      expect(backoff_config.base_interval).to eq(0.5)
    end

    it "multiplier defaults to 1.5" do
      expect(backoff_config.multiplier).to eq(1.5)
    end
  end

  it "generates 10 randomized intervals" do
    expect(described_class.new(tries: 9).intervals).to eq([
      0.43727005942368125,
      0.6559050891355219,
      0.9838576337032829,
      1.4757864505549243,
      2.2136796758323865,
      3.3205195137485797,
      4.98077927062287,
      7.471168905934304,
      11.206753358901457
    ])
  end

  it "generates defined number of intervals" do
    expect(described_class.new(tries: 5).intervals.size).to eq(5)
  end

  it "generates intervals with a defined base interval" do
    expect(described_class.new(base_interval: 1).intervals).to eq([
      0.8745401188473625,
      1.3118101782710438,
      1.9677152674065659
    ])
  end

  it "generates intervals with a defined multiplier" do
    expect(described_class.new(multiplier: 1).intervals).to eq([
     0.43727005942368125,
     0.43727005942368125,
     0.43727005942368125
   ])
  end

  it "generates intervals with a defined max interval" do
    expect(described_class.new(max_interval: 1.0, rand_factor: 0.0).intervals).to eq([0.5, 0.75, 1.0])
  end

  it "generates intervals with a defined rand_factor" do
    expect(described_class.new(rand_factor: 0.2).intervals).to eq([
      0.47490802376947255,
      0.7123620356542087,
      1.0685430534813132
    ])
  end

  it "generates 10 non-randomized intervals" do
    non_random_intervals = 9.times.inject([0.5]) { |memo, _i| memo + [memo.last * 1.5] }
    expect(described_class.new(tries: 10, rand_factor: 0.0).intervals).to eq(non_random_intervals)
  end
end
