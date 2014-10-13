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

    it "stops at first try if the block does not raise an exception" do
      tries = 0
      subject.retriable do
        tries += 1
      end

      tries.must_equal 1
    end

    it "raises a LocalJumpError if #retriable is not given a block" do
      -> do
        subject.retriable on: StandardError
      end.must_raise LocalJumpError

      -> do
        subject.retriable on: StandardError, timeout: 2
      end.must_raise LocalJumpError
    end

    it "makes 3 tries when retrying block of code raising StandardError with no arguments" do
      tries = 0

      -> do
        subject.retriable do
          tries += 1
          raise StandardError.new
        end
      end.must_raise StandardError

      tries.must_equal 3
    end

    it "makes only 1 try when exception raised is not ancestor of StandardError" do
      tries = 0

      -> do
        subject.retriable do
          tries += 1
          raise TestError.new
        end
      end.must_raise TestError

      tries.must_equal 1
    end

    it "#retriable with custom exception tries 3  times and re-raises the exception" do
      tries = 0
      -> do
        subject.retriable on: TestError do
          tries += 1
          raise TestError.new
        end
      end.must_raise TestError

      tries.must_equal 3
    end

    it "#retriable tries 10 times" do
      tries = 0

      -> do
        subject.retriable(
          tries: 10
        ) do
            tries += 1
            raise StandardError.new
        end
      end.must_raise StandardError

      tries.must_equal 10
    end

    it "#retriable will timeout after 1 second" do
      -> do
        subject.retriable timeout: 1 do
          sleep 1.1
        end
      end.must_raise Timeout::Error
    end

    it "applies a randomized exponential backoff to each try" do
      @tries = 0
      @time_table = {}

      handler = ->(exception, try, elapsed_time, next_interval) do
        exception.class.must_equal ArgumentError
        @time_table[try] = next_interval
      end

      -> do
        Retriable.retriable(
          on: [EOFError, ArgumentError],
          on_retry: handler,
          rand_factor: 0.0,
          tries: 9
        ) do
          @tries += 1
          raise ArgumentError.new
        end
      end.must_raise ArgumentError

      10000.times do |iteration|
        @time_table[1].between?(0.25, 0.75).must_equal true
        @time_table[2].between?(0.375, 1.125).must_equal true
        @time_table[3].between?(0.5625, 1.6875).must_equal true
        @time_table[4].between?(0.84375, 2.53125).must_equal true
        @time_table[5].between?(1.265625, 3.796875).must_equal true
        @time_table[6].between?(1.8984375, 5.6953125).must_equal true
        @time_table[7].between?(2.84765625, 8.54296875).must_equal true
        @time_table[8].between?(4.271484375, 12.814453125).must_equal true
        @time_table[9].between?(6.4072265625, 19.2216796875).must_equal true
        @time_table.size.must_equal 9
      end
    end

    describe "retries with an on_#retriable handler, 6 max retries, and a 0.0 rand_factor" do
      before do
        tries = 6
        @tries = 0
        @time_table = {}

        handler = ->(exception, try, elapsed_time, next_interval) do
          exception.class.must_equal ArgumentError
          @time_table[try] = next_interval
        end

        Retriable.retriable(
          on: [EOFError, ArgumentError],
          on_retry: handler,
          rand_factor: 0.0,
          tries: tries
        ) do
          @tries += 1
          raise ArgumentError.new if @tries < tries
        end
      end

      it "makes 6 tries" do
        @tries.must_equal 6
      end

      it "applies a non-randomized exponential backoff to each try" do
        @time_table.must_equal({
          1 => 0.5,
          2 => 0.75,
          3 => 1.125,
          4 => 1.6875,
          5 => 2.53125
        })
      end
    end

    it "#retriable has a max interval of 1.5 seconds" do
      tries = 0
      time_table = {}

      handler = ->(exception, try, elapsed_time, next_interval) do
        time_table[try] = next_interval
      end

      -> do
        subject.retriable(
          on: StandardError,
          on_retry: handler,
          rand_factor: 0.0,
          tries: 5,
          max_interval: 1.5
        ) do
          tries += 1
          raise StandardError.new
        end
      end.must_raise StandardError

      time_table.must_equal({
        1 => 0.5,
        2 => 0.75,
        3 => 1.125,
        4 => 1.5,
        5 => 1.5
      })
    end

    it "#retriable with custom defined intervals" do
      intervals = [
        0.5,
        0.75,
        1.125,
        1.5,
        1.5
      ]
      time_table = {}

      handler = ->(exception, try, elapsed_time, next_interval) do
        time_table[try] = next_interval
      end

      -> do
        subject.retriable(
          on_retry: handler,
          intervals: intervals
        ) do
          raise StandardError.new
        end
      end.must_raise StandardError

      time_table.must_equal({
        1 => 0.5,
        2 => 0.75,
        3 => 1.125,
        4 => 1.5,
        5 => 1.5
      })
    end

    it "#retriable with a hash exception where the value is an exception message pattern" do
      e = -> do
        subject.retriable on: { TestError => /something went wrong/ } do
          raise TestError.new('something went wrong')
        end
      end.must_raise TestError

      e.message.must_equal "something went wrong"
    end

    it "#retriable with a hash exception list where the values are exception message patterns" do
      tries = 0
      exceptions = []
      handler = ->(exception, try, elapsed_time, next_interval) do
        exceptions[try] = exception
      end

      e = -> do
        subject.retriable tries: 4, on: { StandardError => nil, TestError => [/foo/, /bar/] }, on_retry: handler do
          tries += 1
          case tries
          when 1
            raise TestError.new('foo')
          when 2
            raise TestError.new('bar')
          when 3
            raise StandardError.new
          else
            raise TestError.new('crash')
          end
        end
      end.must_raise TestError

      e.message.must_equal "crash"
      exceptions[1].class.must_equal TestError
      exceptions[1].message.must_equal "foo"
      exceptions[2].class.must_equal TestError
      exceptions[2].message.must_equal "bar"
      exceptions[3].class.must_equal StandardError
    end

    it "#retriable can be called in the global scope" do
      -> do
        retriable do
          puts "should raise NoMethodError"
        end
      end.must_raise NoMethodError

      require_relative "../lib/retriable/core_ext/kernel"

      tries = 0

      -> do
        retriable do
          tries += 1
          raise StandardError.new
        end
      end.must_raise StandardError

      tries.must_equal 3
    end
  end

  it "#retriable runs for a max elapsed time of 2 seconds" do
    subject.configure do |c|
      c.sleep_disabled = false
    end

    subject.config.sleep_disabled.must_equal false

    tries = 0
    time_table = {}

    handler = ->(exception, try, elapsed_time, next_interval) do
      time_table[try] = elapsed_time
    end

    -> do
      subject.retriable(
        base_interval: 1.0,
        multiplier: 1.0,
        rand_factor: 0.0,
        max_elapsed_time: 2.0,
        on_retry: handler
      ) do
        tries += 1
        raise EOFError.new
      end
    end.must_raise EOFError

    tries.must_equal 2
  end
end
