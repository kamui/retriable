describe Retriable do
  let(:time_table_handler) do
    lambda do |_exception, try, _elapsed_time, next_interval|
      @next_interval_table[try] = next_interval
    end
  end

  before(:each) do
    @tries = 0
    @next_interval_table = {}
  end

  def increment_tries
    @tries += 1
  end

  def increment_tries_with_exception(exception_class)
    increment_tries
    raise exception_class, "#{exception_class} occurred"
  end

  context "with sleep disabled" do
    before do
      Retriable.configure do |c|
        c.sleep_disabled = true
      end
    end

    it "stops at first try if the block does not raise an exception" do
      described_class.retriable { increment_tries }
      expect(@tries).to eq(1)
    end

    it "raises a LocalJumpError if #retriable is not given a block" do
      expect { described_class.retriable(on: StandardError) }.to raise_error(LocalJumpError)
      expect { described_class.retriable(on: StandardError, timeout: 2) }.to raise_error(LocalJumpError)
    end

    it "makes 3 tries when retrying block of code raising StandardError with no arguments" do
      expect do
        described_class.retriable { increment_tries_with_exception(StandardError) }
      end.to raise_error(StandardError)

      expect(@tries).to eq(3)
    end

    it "makes only 1 try when exception raised is not ancestor of StandardError" do
      expect do
        described_class.retriable { increment_tries_with_exception(TestError) }
      end.to raise_error(TestError)

      expect(@tries).to eq(1)
    end

    it "#retriable with custom exception tries 3 times and re-raises the exception" do
      expect do
        described_class.retriable(on: TestError) { increment_tries_with_exception(TestError) }
      end.to raise_error(TestError)

      expect(@tries).to eq(3)
    end

    it "#retriable tries 10 times" do
      expect do
        described_class.retriable(tries: 10) { increment_tries_with_exception(StandardError) }
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
      expect do
        Retriable.retriable(on: [EOFError, ArgumentError], on_retry: time_table_handler, tries: 10) do
          increment_tries_with_exception(ArgumentError)
        end
      end.to raise_error(ArgumentError)

      expect(@next_interval_table).to eq(
        1 => 0.5244067512211441,
        2 => 0.9113920238761231,
        3 => 1.2406087918999114,
        4 => 1.7632403621664823,
        5 => 2.338001204738311,
        6 => 4.350816718580626,
        7 => 5.339852157217869,
        8 => 11.889873261212443,
        9 => 18.756037881636484,
        10 => nil,
      )

      expect(@tries).to eq(10)
    end

    context "rand_factor 0.0" do
      let(:no_rand_timetable) do
        {
          1 => 0.5,
          2 => 0.75,
          3 => 1.125
        }
      end

      context "retries with an on_#retriable handler, 6 max retries, and a 0.0 rand_factor" do
        let(:tries) { 6 }

        before do
          Retriable.retriable(
            on: [EOFError, ArgumentError],
            on_retry: time_table_handler,
            rand_factor: 0.0,
            tries: tries,
          ) do
            @tries += 1
            raise ArgumentError, "ArgumentError occurred" if @tries < tries
          end
        end

        it "applies a non-randomized exponential backoff to each try" do
          expect(@tries).to eq(tries)
          expect(@next_interval_table).to eq(no_rand_timetable.merge(4 => 1.6875, 5 => 2.53125))
        end
      end

      it "#retriable has a max interval of 1.5 seconds" do
        expect do
          described_class.retriable(
            on: StandardError,
            on_retry: time_table_handler,
            rand_factor: 0.0,
            tries: 5,
            max_interval: 1.5,
          ) do
            increment_tries_with_exception(StandardError)
          end
        end.to raise_error(StandardError)

        expect(@next_interval_table).to eq(no_rand_timetable.merge(4 => 1.5, 5 => nil))
      end
    end

    it "#retriable with custom defined intervals" do
      intervals = [
        0.5,
        0.75,
        1.125,
        1.5,
        1.5,
      ]

      expect do
        described_class.retriable(on_retry: time_table_handler, intervals: intervals) do
          increment_tries_with_exception(StandardError)
        end
      end.to raise_error(StandardError)

      expect(@next_interval_table).to eq(
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
      let(:error_message) { "something went wrong" }
      let(:on_hash_argument) { { TestError => /TestError occurred/ } }

      it "#retriable with a hash exception where the value is an exception message pattern" do
        expect do
          described_class.retriable(on: on_hash_argument) { raise TestError, "TestError occurred" }
        end.to raise_error(TestError, /TestError occurred/)
      end

      it "#retriable with a hash exception list matches exception subclasses" do
        on_hash = on_hash_argument.merge(
          DifferentTestError => /should never happen/,
          DifferentTestError => /also should never happen/
        )

        expect do
          described_class.retriable(tries: 4, on: on_hash) { increment_tries_with_exception(SecondTestError) }
        end.to raise_error(SecondTestError, /SecondTestError occurred/)

        expect(@tries).to eq(4)
      end

      it "#retriable does not retry matching exception subclass but not message" do
        expect do
          described_class.retriable(on: on_hash_argument, tries: 4) do
            @tries += 1
            raise SecondTestError, "not a match"
          end
        end.to raise_error(SecondTestError, /not a match/)

        expect(@tries).to eq(1)
      end

      it "retries when the values are arrays of exception message patterns" do
        exceptions = []
        handler = lambda do |exception, try, _elapsed_time, _next_interval|
          exceptions[try] = exception
        end

        expect do
          described_class.retriable(tries: 4, on: { StandardError => nil, TestError => [/foo/, /bar/] }, on_retry: handler) do
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
    end

    context "global scope extension" do
      it "cannot be called in the global scope without requiring the core_ext/kernel" do
        expect { retriable { puts "should raise NoMethodError" } }.to raise_error(NoMethodError)
      end

      it "can be called once the kernel extension is required" do
        require_relative "../lib/retriable/core_ext/kernel"

        expect { retriable { increment_tries_with_exception(StandardError) } }.to raise_error(StandardError)
        expect(@tries).to eq(3)
      end
    end
  end

  it "#retriable runs for a max elapsed time of 2 seconds" do
    described_class.configure do |c|
      c.sleep_disabled = false
    end

    expect do
      described_class.retriable(
        base_interval: 1.0,
        multiplier: 1.0,
        rand_factor: 0.0,
        max_elapsed_time: 2.0
      ) do
        increment_tries_with_exception(EOFError)
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
      described_class.with_context(:sql) { increment_tries }
      expect(@tries).to eq(1)
    end

    it "with_context respects the context options" do
      expect do
        described_class.with_context(:api) { increment_tries_with_exception(StandardError) }
      end.to raise_error(StandardError)

      expect(@tries).to eq(3)
    end

    it "with_context allows override options" do
      expect do
        described_class.with_context(:sql, tries: 5) { increment_tries_with_exception(StandardError) }
      end.to raise_error(StandardError)

      expect(@tries).to eq(5)
    end

    it "raises an ArgumentError when the context isn't found" do
      expect do
        described_class.with_context(:wtf) { increment_tries }
      end.to raise_error(ArgumentError, /wtf not found/)
    end
  end
end
