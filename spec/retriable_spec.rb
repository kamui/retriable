require_relative "spec_helper"

class TestError < Exception; end

describe Retriable do
  subject do
    Retriable
  end

  before do
    srand 0
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

    it "#retriable with custom exception tries 3 times and re-raises the exception" do
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
      @time_table = []

      handler = ->(exception, try, elapsed_time, next_interval) do
        exception.class.must_equal ArgumentError
        @time_table << next_interval
      end

      -> do
        Retriable.retriable(
          on: [EOFError, ArgumentError],
          on_retry: handler,
          tries: 9
        ) do
          @tries += 1
          raise ArgumentError.new
        end
      end.must_raise ArgumentError

      @time_table.must_equal([
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
