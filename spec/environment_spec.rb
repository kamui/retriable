require_relative 'spec_helper'

describe Retriable do
  subject do
    Retriable
  end

  before do
    Retriable.reset!
  end

  after do
    Retriable.reset!
  end

  it "accepts environment configurations" do
    Retriable.configure do |config|
      config.environments = { ecs: { max_elapsed_time: 500 } }
    end
  end

  it "raises errors on invalid configuration" do
    assert_raises ArgumentError do
      Retriable.configure do |config|
        config.environments = { aws: { yo: 'mtv raps' } }
      end
    end

    assert_raises ArgumentError do
      Retriable.configure do |config|
        config.environments = { aws: 'yo' }
      end
    end

    assert_raises ArgumentError do
      Retriable.configure do |config|
        config.environments = 'yo'
      end
    end

    assert_raises ArgumentError do
      Retriable.configure do |config|
        config.environments = { retriable: { max_elapsed_time: 500 } }
      end
    end
  end

  it "additional_environments can be added" do
    Retriable.configure do |config|
      config.environments = { aws: { max_elapsed_time: 500 } }
    end

    Retriable.configure do |config|
      config.environments[:s3] = { max_elapsed_time: 1500 }
    end

    Retriable.aws
    Retriable.s3
  end

  it 'will not use a nonexistent environment' do
    expect do
      Retriable.heroku.retriable do
        tries += 1
        raise EOFError.new
      end
    end.must_raise NoMethodError
  end

  it 'uses a configured environment' do
    tries = 0

    subject.configure do |c|
      c.environments[:aws] = {
        base_interval: 0.1,
        multiplier: 0.1,
        tries: 5
      }
    end

    expect do
      Retriable.aws.retriable do
        tries += 1
        raise EOFError.new
      end
    end.must_raise EOFError

    expect(tries).must_equal(5)
  end
end
