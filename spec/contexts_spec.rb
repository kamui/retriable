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

  it "accepts context configurations" do
    Retriable.configure do |config|
      config.contexts = { ecs: { max_elapsed_time: 500 } }
    end
  end

  it "raises errors on invalid configuration" do
    assert_raises ArgumentError do
      Retriable.configure do |config|
        config.contexts = { aws: { yo: 'mtv raps' } }
      end
      Retriable.aws { 1 + 1 }
    end

    assert_raises ArgumentError do
      Retriable.configure do |config|
        config.contexts = { aws: 'yo' }
      end
      Retriable.aws { 1 + 1 }
    end

    assert_raises ArgumentError do
      Retriable.configure do |config|
        config.contexts = 'yo'
      end
    end
  end

  it "additional_contexts can be added" do
    Retriable.configure do |config|
      config.contexts = { aws: { max_elapsed_time: 500 } }
    end

    Retriable.configure do |config|
      config.contexts[:s3] = { max_elapsed_time: 1500 }
    end

    Retriable.aws
    Retriable.s3
  end

  it 'will not use a nonexistent context' do
    expect do
      Retriable.heroku do
        tries += 1
        raise EOFError.new
      end
    end.must_raise NoMethodError
  end

  it 'uses a configured context' do
    tries = 0

    subject.configure do |c|
      c.contexts[:aws] = {
        base_interval: 0.1,
        multiplier: 0.1,
        tries: 5
      }
    end

    expect do
      Retriable.aws do
        tries += 1
        raise EOFError
      end
    end.must_raise EOFError

    expect(tries).must_equal(5)
  end

  it 'overloads part of a configured context' do
    tries = 0

    subject.configure do |c|
      c.contexts[:aws] = {
        base_interval: 0.1,
        multiplier: 0.1,
        tries: 5
      }
    end

    expect do
      Retriable.aws(tries: 10) do
        tries += 1
        raise EOFError
      end
    end.must_raise EOFError

    expect(tries).must_equal(10)
  end
end
