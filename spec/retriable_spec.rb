require_relative 'spec_helper'

class TestError < Exception; end

describe Retriable do
  subject do
    Retriable
  end

  describe 'with sleep disabled' do
    before do
      Retriable.configure do |c|
        c.sleep_disabled = true
      end
    end

    it 'raises a LocalJumpError if retry is not given a block' do
      lambda do
        subject.retry on: EOFError
      end.must_raise LocalJumpError
    end

    describe 'retry block of code raising EOFError with no arguments' do
      before do
        @attempts = 0

        subject.retry do
          @attempts += 1
          raise EOFError.new if @attempts < 3
        end
      end

      it 'uses exponential backoff' do
        @attempts.must_equal 3
      end
    end

    it 'retry on custom exception and re-raises the exception' do
      lambda do
        subject.retry on: TestError do
          raise TestError.new
        end
      end.must_raise TestError
    end

    it 'retry with 10 max tries' do
      attempts = 0

      subject.retry(
        max_tries: 10
      ) do
          attempts += 1
          raise EOFError.new if attempts < 10
      end

      attempts.must_equal 10
    end

    it 'retry will timeout after 1 second' do
      lambda do
        subject.retry timeout: 1 do
          sleep 2
        end
      end.must_raise Timeout::Error
    end

    describe 'retries with an on_retry handler, 6 max retries, and a 0.0 rand_factor' do
      before do
        max_tries = 6
        @attempts = 0
        @time_table = {}

        handler = Proc.new do |exception, attempt, elapsed_time, next_interval|
          exception.class.must_equal ArgumentError
          @time_table[attempt] = next_interval
        end

        Retriable.retry(
          on: [EOFError, ArgumentError],
          on_retry: handler,
          rand_factor: 0.0,
          max_tries: max_tries
        ) do
          @attempts += 1
          raise ArgumentError.new if @attempts < max_tries
        end
      end

      it 'makes 6 attempts' do
        @attempts.must_equal 6
      end

      it 'applies a non-randomized exponential backoff to each attempt' do
        @time_table.must_equal({
          1 => 0.5,
          2 => 0.75,
          3 => 1.125,
          4 => 1.6875,
          5 => 2.53125
        })
      end
    end

    it 'retry has a max interval of 1.5 seconds' do
      max_tries = 6
      attempts = 0
      time_table = {}

      handler = Proc.new do |exception, attempt, elapsed_time, next_interval|
        time_table[attempt] = next_interval
      end

      subject.retry(
        on: EOFError,
        on_retry: handler,
        rand_factor: 0.0,
        max_tries: max_tries,
        max_interval: 1.5
      ) do
        attempts += 1
        raise EOFError.new if attempts < max_tries
      end

      time_table.must_equal({
        1 => 0.5,
        2 => 0.75,
        3 => 1.125,
        4 => 1.5,
        5 => 1.5
      })
    end

    it 'can call #retriable in the global' do
      lambda do
        retriable do
          puts 'should raise NoMethodError'
        end
      end.must_raise NoMethodError

      require_relative '../lib/retriable/core_ext/kernel'

      i = 0
      retriable do
        i += 1
        raise EOFError.new if i < 3
      end
      i.must_equal 3
    end
  end

  it 'retry runs for a max elapsed time of 2 seconds' do
    subject.configure do |c|
      c.sleep_disabled = false
    end

    subject.config.sleep_disabled.must_equal false

    attempts = 0
    time_table = {}

    handler = Proc.new do |exception, attempt, elapsed_time, next_interval|
      time_table[attempt] = elapsed_time
    end

    lambda do
      subject.retry(
        base_interval: 1.0,
        multiplier: 1.0,
        rand_factor: 0.0,
        max_elapsed_time: 2.0,
        on_retry: handler
      ) do
        attempts += 1
        raise EOFError.new
      end
    end.must_raise EOFError

    attempts.must_equal 2
  end
end
