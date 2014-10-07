require_relative "spec_helper"

class TestError < Exception; end

describe Retriable do
  subject do
    Retriable
  end

  describe "with sleep disabled" do
    before do
      Retriable.configure do |c|
        c.sleep_disabled = true
      end
    end

    it "stops at first attempt if the block does not raise an exception" do
      attempts = 0
      subject.retry do
        attempts += 1
      end

      attempts.must_equal 1
    end

    it "raises a LocalJumpError if retry is not given a block" do
      -> do
        subject.retry on: EOFError
      end.must_raise LocalJumpError

      -> do
        subject.retry on: EOFError, timeout: 2
      end.must_raise LocalJumpError
    end

    describe "retry block of code raising EOFError with no arguments" do
      before do
        @attempts = 0

        subject.retry do
          @attempts += 1
          raise EOFError.new if @attempts < 3
        end
      end

      it "uses exponential backoff" do
        @attempts.must_equal 3
      end
    end

    it "retry on custom exception and re-raises the exception" do
      -> do
        subject.retry on: TestError do
          raise TestError.new
        end
      end.must_raise TestError
    end

    it "retry with 10 max tries" do
      attempts = 0

      subject.retry(
        max_tries: 10
      ) do
          attempts += 1
          raise EOFError.new if attempts < 10
      end

      attempts.must_equal 10
    end

    it "retry will timeout after 1 second" do
      -> do
        subject.retry timeout: 1 do
          sleep 2
        end
      end.must_raise Timeout::Error
    end

    it "applies a randomized exponential backoff to each attempt" do
      @attempts = 0
      @time_table = {}

      handler = ->(exception, attempt, elapsed_time, next_interval) do
        exception.class.must_equal ArgumentError
        @time_table[attempt] = next_interval
      end

      -> do
        Retriable.retry(
          on: [EOFError, ArgumentError],
          on_retry: handler,
          rand_factor: 0.0,
          max_tries: 9
        ) do
          @attempts += 1
          raise ArgumentError.new
        end
      end.must_raise ArgumentError

      @time_table[1].between?(0.25, 0.75).must_equal true
      @time_table[2].between?(0.375, 1.125).must_equal true
      @time_table[3].between?(0.562, 1.687).must_equal true
      @time_table[4].between?(0.8435, 2.53).must_equal true
      @time_table[5].between?(1.265, 3.795).must_equal true
      @time_table[6].between?(1.897, 5.692).must_equal true
      @time_table[7].between?(2.846, 8.538).must_equal true
      @time_table[8].between?(4.269, 12.807).must_equal true
      @time_table[9].between?(6.403, 19.210).must_equal true
    end

    describe "retries with an on_retry handler, 6 max retries, and a 0.0 rand_factor" do
      before do
        max_tries = 6
        @attempts = 0
        @time_table = {}

        handler = ->(exception, attempt, elapsed_time, next_interval) do
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

      it "makes 6 attempts" do
        @attempts.must_equal 6
      end

      it "applies a non-randomized exponential backoff to each attempt" do
        @time_table.must_equal({
          1 => 0.5,
          2 => 0.75,
          3 => 1.125,
          4 => 1.6875,
          5 => 2.53125
        })
      end
    end

    it "retry has a max interval of 1.5 seconds" do
      max_tries = 6
      attempts = 0
      time_table = {}

      handler = ->(exception, attempt, elapsed_time, next_interval) do
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

    it "retries with defined intervals" do
      intervals = [
        0.5,
        0.75,
        1.125,
        1.5,
        1.5
      ]
      time_table = {}

      handler = ->(exception, attempt, elapsed_time, next_interval) do
        time_table[attempt] = next_interval
      end

      -> do
        subject.retry(
          on: EOFError,
          on_retry: handler,
          intervals: intervals
        ) do
          raise EOFError.new
        end
      end.must_raise EOFError

      time_table.must_equal({
        1 => 0.5,
        2 => 0.75,
        3 => 1.125,
        4 => 1.5,
        5 => 1.5
      })
    end

    it "retries with a hash exception where the value is an exception message pattern" do
      e = -> do
        subject.retry on: { TestError => /something went wrong/ } do
          raise TestError.new('something went wrong')
        end
      end.must_raise TestError

      e.message.must_equal "something went wrong"
    end

    it "retries with a hash exception list where the values are exception message patterns" do
      attempts = 0
      tries = []
      handler = ->(exception, attempt, elapsed_time, next_interval) do
        tries[attempt] = exception
      end

      e = -> do
        subject.retry max_tries: 4, on: { EOFError => nil, TestError => [/foo/, /bar/] }, on_retry: handler do
          attempts += 1
          case attempts
          when 1
            raise TestError.new('foo')
          when 2
            raise TestError.new('bar')
          when 3
            raise EOFError.new
          else
            raise TestError.new('crash')
          end
        end
      end.must_raise TestError

      e.message.must_equal "crash"
      tries[1].class.must_equal TestError
      tries[1].message.must_equal "foo"
      tries[2].class.must_equal TestError
      tries[2].message.must_equal "bar"
      tries[3].class.must_equal EOFError
    end

    it "can call #retriable in the global" do
      -> do
        retriable do
          puts "should raise NoMethodError"
        end
      end.must_raise NoMethodError

      require_relative "../lib/retriable/core_ext/kernel"

      i = 0
      retriable do
        i += 1
        raise EOFError.new if i < 3
      end
      i.must_equal 3
    end
  end

  it "retry runs for a max elapsed time of 2 seconds" do
    subject.configure do |c|
      c.sleep_disabled = false
    end

    subject.config.sleep_disabled.must_equal false

    attempts = 0
    time_table = {}

    handler = ->(exception, attempt, elapsed_time, next_interval) do
      time_table[attempt] = elapsed_time
    end

    -> do
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
