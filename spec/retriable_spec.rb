require_relative "spec_helper"

describe Retriable do
  before do
    @tries = 0
  end

  describe "with sleep disabled" do
    before do
      Retriable.configure do |c|
        c.sleep_disabled = true
      end
    end

    it "stops at first try if the block does not raise an exception" do
      described_class.retriable { @tries += 1 }
      expect(@tries).to eq(1)
    end

    it "raises a LocalJumpError if #retriable is not given a block" do
      expect { described_class.retriable on: StandardError }.to raise_error(LocalJumpError)
      expect { described_class.retriable on: StandardError, timeout: 2 }.to raise_error(LocalJumpError)
    end

    it "makes 3 tries when retrying block of code raising StandardError with no arguments" do
      expect do
        described_class.retriable do
          @tries += 1
          raise StandardError.new, "StandardError occurred"
        end
      end.to raise_error(StandardError)

      expect(@tries).to eq(3)
    end

    it "makes only 1 try when exception raised is not ancestor of StandardError" do
      expect do
        described_class.retriable do
          @tries += 1
          raise TestError.new, "TestError occurred"
        end
      end.to raise_error(TestError)

      expect(@tries).to eq(1)
    end

    it "#retriable with custom exception tries 3 times and re-raises the exception" do
      expect do
        described_class.retriable(on: TestError) do
          @tries += 1
          raise TestError.new, "TestError occurred"
        end
      end.to raise_error(TestError)

      expect(@tries).to eq(3)
    end

    it "#retriable tries 10 times" do
      expect do
        described_class.retriable(tries: 10) do
          @tries += 1
          raise StandardError.new, "StandardError occurred"
        end
      end.to raise_error(StandardError)

      expect(@tries).to eq(10)
    end

    it "#retriable will timeout after 1 second" do
      expect do
        described_class.retriable(timeout: 1) do
          sleep(1.1)
        end
      end.to raise_error(Timeout::Error)
    end

    it "applies a randomized exponential backoff to each try" do
      time_table = []

      handler = lambda do |exception, _try, _elapsed_time, next_interval|
        expect(exception.class).to eq(ArgumentError)
        time_table << next_interval
      end

      expect do
        Retriable.retriable(on: [EOFError, ArgumentError], on_retry: handler, tries: 10) do
          @tries += 1
          raise ArgumentError.new, "ArgumentError occurred"
        end
      end.to raise_error(ArgumentError)

      expect(time_table).to eq([
        0.5244067512211441,
        0.9113920238761231,
        1.2406087918999114,
        1.7632403621664823,
        2.338001204738311,
        4.350816718580626,
        5.339852157217869,
        11.889873261212443,
        18.756037881636484,
        nil,
      ])

      expect(@tries).to eq(10)
    end

    describe "retries with an on_#retriable handler, 6 max retries, and a 0.0 rand_factor" do
      before do
        tries = 6
        @try_count = 0
        @time_table = {}

        handler = lambda do |exception, try, _elapsed_time, next_interval|
          expect(exception.class).to eq(ArgumentError)
          @time_table[try] = next_interval
        end

        Retriable.retriable(
          on: [EOFError, ArgumentError],
          on_retry: handler,
          rand_factor: 0.0,
          tries: tries,
        ) do
          @try_count += 1
          raise ArgumentError.new, "ArgumentError occurred" if @try_count < tries
        end
      end

      it "makes 6 tries" do
        expect(@try_count).to eq(6)
      end

      it "applies a non-randomized exponential backoff to each try" do
        expect(@time_table).to eq(
          1 => 0.5,
          2 => 0.75,
          3 => 1.125,
          4 => 1.6875,
          5 => 2.53125,
        )
      end
    end

    it "#retriable has a max interval of 1.5 seconds" do
      time_table = {}

      handler = lambda do |_exception, try, _elapsed_time, next_interval|
        time_table[try] = next_interval
      end

      expect do
        described_class.retriable(
          on: StandardError,
          on_retry: handler,
          rand_factor: 0.0,
          tries: 5,
          max_interval: 1.5,
        ) do
          @tries += 1
          raise StandardError.new
        end
      end.to raise_error(StandardError)

      expect(time_table).to eq(
        1 => 0.5,
        2 => 0.75,
        3 => 1.125,
        4 => 1.5,
        5 => nil,
      )
    end

    it "#retriable with custom defined intervals" do
      intervals = [
        0.5,
        0.75,
        1.125,
        1.5,
        1.5,
      ]
      time_table = {}

      handler = lambda do |_exception, try, _elapsed_time, next_interval|
        time_table[try] = next_interval
      end

      expect do
        described_class.retriable(
          on_retry: handler,
          intervals: intervals,
        ) do
          @tries += 1
          raise StandardError.new
        end
      end.to raise_error(StandardError)

      expect(time_table).to eq(
        1 => 0.5,
        2 => 0.75,
        3 => 1.125,
        4 => 1.5,
        5 => 1.5,
        6 => nil,
      )

      expect(@tries).to eq(6)
    end

    context "hash exception list" do
      let(:error_message) { 'something went wrong' }
      let(:hash_argument) { { TestError => /#{error_message}/ } }

      it "#retriable with a hash exception where the value is an exception message pattern" do
        expect do
          described_class.retriable(on: hash_argument) { raise TestError, error_message }
        end.to raise_error(TestError, /#{error_message}/)
      end

      it "#retriable with a hash exception list matches exception subclasses" do
        on_hash = hash_argument.merge(
          DifferentTestError => /should never happen/,
          DifferentTestError => /also should never happen/
        )

        expect do
          described_class.retriable(tries: 4, on: on_hash, tries: 4) do
            @tries += 1
            raise SecondTestError, error_message
          end
        end.to raise_error(SecondTestError, /something went wrong/)

        expect(@tries).to eq(4)
      end

      it "#retriable with a hash exception list does not retry matching exception subclass but not message" do
        expect do
          described_class.retriable(on: hash_argument, tries: 4) do
            @tries += 1
            raise SecondTestError, "not a match"
          end
        end.to raise_error(SecondTestError, /not a match/)

        expect(@tries).to eq(1)
      end
    end



    it "#retriable with a hash exception list where the values are exception message patterns" do
      exceptions = []
      handler = lambda do |exception, try, _elapsed_time, _next_interval|
        exceptions[try] = exception
      end

      e = expect do
        described_class.retriable tries: 4, on: { StandardError => nil, TestError => [/foo/, /bar/] }, on_retry: handler do
          @tries += 1

          case @tries
          when 1
            raise TestError, "foo"
          when 2
            raise TestError, "bar"
          when 3
            raise StandardError
          else
            raise TestError, "crash"
          end
        end
      end.to raise_error(TestError, /crash/)

      expect(exceptions[1].class).to eq(TestError)
      expect(exceptions[1].message).to eq("foo")
      expect(exceptions[2].class).to eq(TestError)
      expect(exceptions[2].message).to eq("bar")
      expect(exceptions[3].class).to eq(StandardError)
    end

    it "#retriable cannot be called in the global scope without requiring the core_ext/kernel" do
      expect do
        retriable do
          puts "should raise NoMethodError"
        end
      end.to raise_error(NoMethodError)

      require_relative "../lib/retriable/core_ext/kernel"

      expect do
        retriable do
          @tries += 1
          raise StandardError
        end
      end.to raise_error(StandardError)

      expect(@tries).to eq(3)
    end
  end

  it "#retriable runs for a max elapsed time of 2 seconds" do
    described_class.configure do |c|
      c.sleep_disabled = false
    end

    expect(described_class.config.sleep_disabled).to be_falsey

    time_table = {}

    handler = lambda do |_exception, try, elapsed_time, _next_interval|
      time_table[try] = elapsed_time
    end

    expect do
      described_class.retriable(
        base_interval: 1.0,
        multiplier: 1.0,
        rand_factor: 0.0,
        max_elapsed_time: 2.0,
        on_retry: handler,
      ) do
        @tries += 1
        raise EOFError
      end
    end.to raise_error(EOFError)

    expect(@tries).to eq(2)
  end

  it "raises NoMethodError on invalid configuration" do
    expect { Retriable.configure { |c| c.does_not_exist = 123 } }.to raise_error(NoMethodError)
  end

  it "raises ArgumentError on invalid option on #retriable" do
    expect { Retriable.retriable(does_not_exist: 123) }.to raise_error(ArgumentError)
  end

  describe "#with_context" do
    before do
      Retriable.configure do |c|
        c.sleep_disabled = true
        c.contexts[:sql] = { tries: 1 }
        c.contexts[:api] = { tries: 3 }
      end
    end

    it "sql context stops at first try if the block does not raise an exception" do
      described_class.with_context(:sql) do
        @tries += 1
      end

      expect(@tries).to eq(1)
    end

    it "with_context respects the context options" do
      expect do
        described_class.with_context(:api) do
          @tries += 1
          raise StandardError.new, "StandardError occurred"
        end
      end.to raise_error(StandardError)

      expect(@tries).to eq(3)
    end

    it "with_context allows override options" do
      expect do
        described_class.with_context(:sql, tries: 5) do
          @tries += 1
          raise StandardError.new, "StandardError occurred"
        end
      end.to raise_error(StandardError)

      expect(@tries).to eq(5)
    end

    it "raises an ArgumentError when the context isn't found" do
      expect do
        described_class.with_context(:wtf) do
          @tries += 1
        end
      end.to raise_error(ArgumentError, /wtf not found/)
    end
  end
end
