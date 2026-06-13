# frozen_string_literal: true

require "rbconfig"

describe Retriable do
  let(:time_table_handler) do
    ->(_exception, try, _elapsed_time, next_interval) { @next_interval_table[try] = next_interval }
  end

  before(:each) do
    described_class.instance_variable_set(:@config, nil)
    Thread.current.thread_variable_set(Retriable::OVERRIDE_THREAD_KEY, nil)
    described_class.configure { |c| c.sleep_disabled = true }
    @tries = 0
    @next_interval_table = {}
  end

  def increment_tries
    @tries += 1
  end

  def increment_tries_with_exception(exception_class = nil)
    exception_class ||= StandardError
    increment_tries
    raise exception_class, "#{exception_class} occurred"
  end

  context "global scope extension" do
    it "cannot be called in the global scope without requiring the core_ext/kernel" do
      script = "require 'retriable'; begin; retriable {}; rescue NoMethodError; exit 0; end; exit 1"

      expect(system(RbConfig.ruby, "-Ilib", "-e", script)).to be(true)
    end

    it "can be called once the kernel extension is required" do
      require_relative "../lib/retriable/core_ext/kernel"

      expect { retriable { increment_tries_with_exception } }.to raise_error(StandardError)
      expect(@tries).to eq(3)
    end

    it "passes on_give_up through the kernel extension" do
      require_relative "../lib/retriable/core_ext/kernel"
      received_reason = nil
      handler = proc { |_e, _try, _elapsed, _interval, reason| received_reason = reason }

      expect { retriable(tries: 1, on_give_up: handler) { increment_tries_with_exception } }
        .to raise_error(StandardError)

      expect(received_reason).to eq(:tries_exhausted)
    end

    # These two specs lock in the anonymous block forwarding (`&`) semantics
    # across both delegation layers: Kernel#retriable_with_context ->
    # Retriable.with_context. If the `&` is dropped at either layer, the block
    # is not forwarded and the `block_given?` guard in with_context raises
    # ArgumentError instead of running the block.
    it "forwards a block through Kernel#retriable_with_context" do
      require_relative "../lib/retriable/core_ext/kernel"
      Retriable.configure { |c| c.contexts[:sql] = { tries: 1 } }

      retriable_with_context(:sql) { increment_tries }

      expect(@tries).to eq(1)
    end

    it "raises an ArgumentError when Kernel#retriable_with_context is called without a block" do
      require_relative "../lib/retriable/core_ext/kernel"
      Retriable.configure { |c| c.contexts[:sql] = { tries: 1 } }

      expect { retriable_with_context(:sql) }
        .to raise_error(ArgumentError, /with_context requires a block/)
      expect(@tries).to eq(0)
    end

    it "is not callable with an explicit receiver" do
      require_relative "../lib/retriable/core_ext/kernel"

      expect { "foo".retriable { increment_tries } }
        .to raise_error(NoMethodError, /private method/)
      expect { "foo".retriable_with_context(:sql) { increment_tries } }
        .to raise_error(NoMethodError, /private method/)
    end
  end

  context "#retriable" do
    it "reuses the singleton config when no local options or overrides are provided" do
      expect(described_class::Config).not_to receive(:new)

      described_class.retriable { increment_tries }
      expect(@tries).to eq(1)
    end

    it "raises a LocalJumpError if not given a block" do
      expect { described_class.retriable }.to raise_error(LocalJumpError)
    end

    it "stops at first try if the block does not raise an exception" do
      described_class.retriable { increment_tries }
      expect(@tries).to eq(1)
    end

    it "makes 3 tries when retrying block of code raising StandardError with no arguments" do
      expect { described_class.retriable { increment_tries_with_exception } }.to raise_error(StandardError)
      expect(@tries).to eq(3)
    end

    it "makes only 1 try when exception raised is not descendent of StandardError" do
      expect do
        described_class.retriable { increment_tries_with_exception(NonStandardError) }
      end.to raise_error(NonStandardError)

      expect(@tries).to eq(1)
    end

    it "with custom exception tries 3 times and re-raises the exception" do
      expect do
        described_class.retriable(on: NonStandardError) { increment_tries_with_exception(NonStandardError) }
      end.to raise_error(NonStandardError)

      expect(@tries).to eq(3)
    end

    it "tries 10 times when specified" do
      expect { described_class.retriable(tries: 10) { increment_tries_with_exception } }.to raise_error(StandardError)
      expect(@tries).to eq(10)
    end

    it "does not prebuild generated intervals before the first successful try" do
      interval_for = ->(_index) { raise "interval should not be used" }
      backoff = instance_double(Retriable::ExponentialBackoff, interval_provider: interval_for)
      allow(Retriable::ExponentialBackoff).to receive(:new).and_call_original
      allow(Retriable::ExponentialBackoff).to receive(:new).with(
        hash_including(:base_interval, :multiplier, :max_interval, :rand_factor),
      ).and_return(backoff)

      described_class.retriable(tries: 1_000_000) { increment_tries }

      expect(@tries).to eq(1)
      expect(backoff).to have_received(:interval_provider)
    end

    it "supports unbounded retries until the block succeeds" do
      described_class.retriable(tries: Float::INFINITY, max_elapsed_time: 60) do
        increment_tries
        raise StandardError if @tries < 5
      end

      expect(@tries).to eq(5)
    end

    it "stops unbounded retries at max_elapsed_time" do
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      timeline = [
        start_time,
        start_time,
        start_time,
        start_time + 0.01,
        start_time + 0.01,
        start_time + 0.02,
        start_time + 0.02,
      ]
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { timeline.shift || timeline.last }

      expect do
        described_class.retriable(
          tries: Float::INFINITY,
          base_interval: 0.01,
          multiplier: 1.0,
          rand_factor: 0.0,
          sleep_disabled: true,
          max_elapsed_time: 0.015,
        ) do
          increment_tries_with_exception
        end
      end.to raise_error(StandardError)

      expect(@tries).to eq(3)
    end

    it "raises ArgumentError when tries is Float::INFINITY without a finite max_elapsed_time" do
      expect do
        described_class.retriable(tries: Float::INFINITY, max_elapsed_time: nil) { increment_tries }
      end.to raise_error(ArgumentError, /max_elapsed_time must be a finite number/)
    end

    it "raises ArgumentError when tries is Float::INFINITY with infinite max_elapsed_time" do
      expect do
        described_class.retriable(tries: Float::INFINITY, max_elapsed_time: Float::INFINITY) { increment_tries }
      end.to raise_error(ArgumentError, /max_elapsed_time must be a finite number/)
    end

    it "raises ArgumentError when tries is Float::INFINITY with custom intervals" do
      expect do
        described_class.retriable(tries: Float::INFINITY, intervals: [0.1, 0.2], max_elapsed_time: 60) do
          increment_tries_with_exception
        end
      end.to raise_error(ArgumentError, /intervals cannot be used with tries: Float::INFINITY/)
    end

    it "raises ArgumentError when tries is Float::NAN" do
      expect do
        described_class.retriable(tries: Float::NAN) { increment_tries }
      end.to raise_error(ArgumentError, /tries/)
    end

    it "raises ArgumentError when tries is negative infinity" do
      expect do
        described_class.retriable(tries: -Float::INFINITY) { increment_tries }
      end.to raise_error(ArgumentError, /tries/)
    end

    it "rejects timeout as an unknown option" do
      expect { described_class.retriable(timeout: 1) { :noop } }.to raise_error(ArgumentError, /not a valid option/)
    end

    it "applies a randomized exponential backoff to each try" do
      expect do
        described_class.retriable(on_retry: time_table_handler, tries: 10) { increment_tries_with_exception }
      end.to raise_error(StandardError)

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

    it "does not call on_retry when explicitly set to false" do
      callback_called = false
      original_on_retry = described_class.config.on_retry

      begin
        described_class.configure do |c|
          c.on_retry = proc { |_exception, _try, _elapsed_time, _next_interval| callback_called = true }
        end

        expect do
          described_class.retriable(on_retry: false, tries: 3) { increment_tries_with_exception }
        end.to raise_error(StandardError)

        expect(@tries).to eq(3)
        expect(callback_called).to be(false)
      ensure
        described_class.configure do |c|
          c.on_retry = original_on_retry
        end
      end
    end

    it "does not call on_retry when explicitly set to nil" do
      callback_called = false
      original_on_retry = described_class.config.on_retry

      begin
        described_class.configure do |c|
          c.on_retry = proc { |_exception, _try, _elapsed_time, _next_interval| callback_called = true }
        end

        expect do
          described_class.retriable(on_retry: nil, tries: 3) { increment_tries_with_exception }
        end.to raise_error(StandardError)

        expect(@tries).to eq(3)
        expect(callback_called).to be(false)
      ensure
        described_class.configure do |c|
          c.on_retry = original_on_retry
        end
      end
    end

    it "calls on_give_up with max elapsed time details before re-raising" do
      described_class.configure { |c| c.sleep_disabled = false }
      give_up_calls = []
      on_give_up = proc do |exception, try, elapsed_time, next_interval, reason|
        give_up_calls << [exception, try, elapsed_time, next_interval, reason]
      end

      expect do
        described_class.retriable(
          intervals: [1.0, 1.0],
          max_elapsed_time: 0.5,
          on_give_up: on_give_up,
        ) do
          increment_tries_with_exception
        end
      end.to raise_error(StandardError)

      exception, try, elapsed_time, next_interval, reason = give_up_calls.fetch(0)
      expect(give_up_calls.size).to eq(1)
      expect(exception).to be_a(StandardError)
      expect(exception.message).to eq("StandardError occurred")
      expect(try).to eq(1)
      expect(elapsed_time).to be >= 0
      expect(next_interval).to eq(1.0)
      expect(reason).to eq(:max_elapsed_time)
      expect(@tries).to eq(1)
    end

    it "calls on_give_up with tries exhausted details before re-raising" do
      give_up_calls = []
      on_give_up = proc do |exception, try, elapsed_time, next_interval, reason|
        give_up_calls << [exception, try, elapsed_time, next_interval, reason]
      end

      expect do
        described_class.retriable(tries: 2, on_give_up: on_give_up) { increment_tries_with_exception }
      end.to raise_error(StandardError)

      exception, try, elapsed_time, next_interval, reason = give_up_calls.fetch(0)
      expect(give_up_calls.size).to eq(1)
      expect(exception).to be_a(StandardError)
      expect(exception.message).to eq("StandardError occurred")
      expect(try).to eq(2)
      expect(elapsed_time).to be >= 0
      expect(next_interval).to be_nil
      expect(reason).to eq(:tries_exhausted)
      expect(@tries).to eq(2)
    end

    it "does not call on_give_up when the block eventually succeeds" do
      callback_called = false

      described_class.retriable(tries: 3, on_give_up: proc { callback_called = true }) do
        increment_tries
        raise StandardError if @tries < 2
      end

      expect(callback_called).to be(false)
      expect(@tries).to eq(2)
    end

    it "does not call on_give_up for non-retriable exception types" do
      callback_called = false

      expect do
        described_class.retriable(on_give_up: proc { callback_called = true }) do
          increment_tries_with_exception(NonStandardError)
        end
      end.to raise_error(NonStandardError)

      expect(callback_called).to be(false)
      expect(@tries).to eq(1)
    end

    it "does not call on_give_up when retry_if rejects the exception" do
      callback_called = false

      expect do
        described_class.retriable(
          tries: 3,
          retry_if: ->(_exception) { false },
          on_give_up: proc { callback_called = true },
        ) do
          increment_tries_with_exception
        end
      end.to raise_error(StandardError)

      expect(callback_called).to be(false)
      expect(@tries).to eq(1)
    end

    it "does not call on_give_up when explicitly set to false" do
      callback_called = false
      original_on_give_up = described_class.config.on_give_up

      begin
        described_class.configure do |c|
          c.on_give_up = proc { callback_called = true }
        end

        expect do
          described_class.retriable(on_give_up: false, tries: 1) { increment_tries_with_exception }
        end.to raise_error(StandardError)

        expect(callback_called).to be(false)
      ensure
        described_class.configure do |c|
          c.on_give_up = original_on_give_up
        end
      end
    end

    it "does not call on_give_up when explicitly set to nil" do
      callback_called = false
      original_on_give_up = described_class.config.on_give_up

      begin
        described_class.configure do |c|
          c.on_give_up = proc { callback_called = true }
        end

        expect do
          described_class.retriable(on_give_up: nil, tries: 1) { increment_tries_with_exception }
        end.to raise_error(StandardError)

        expect(callback_called).to be(false)
      ensure
        described_class.configure do |c|
          c.on_give_up = original_on_give_up
        end
      end
    end

    it "calls on_retry before on_give_up when giving up" do
      events = []

      expect do
        described_class.retriable(
          tries: 1,
          on_retry: proc { events << :on_retry },
          on_give_up: proc { events << :on_give_up },
        ) do
          increment_tries_with_exception
        end
      end.to raise_error(StandardError)

      expect(events).to eq(%i[on_retry on_give_up])
    end

    it "propagates exceptions raised inside on_give_up, replacing the original exception" do
      handler = proc { raise "handler exploded" }

      expect do
        described_class.retriable(tries: 1, on_give_up: handler) { increment_tries_with_exception }
      end.to raise_error(RuntimeError, "handler exploded")

      expect(@tries).to eq(1)
    end

    context "with rand_factor 0.0 and an on_retry handler" do
      let(:tries) { 6 }
      let(:no_rand_timetable) { { 1 => 0.5, 2 => 0.75, 3 => 1.125 } }
      let(:args) { { on_retry: time_table_handler, rand_factor: 0.0, tries: tries } }

      it "applies a non-randomized exponential backoff to each try" do
        described_class.retriable(args) do
          increment_tries
          raise StandardError if @tries < tries
        end

        expect(@tries).to eq(tries)
        expect(@next_interval_table).to eq(no_rand_timetable.merge(4 => 1.6875, 5 => 2.53125))
      end

      it "obeys a max interval of 1.5 seconds" do
        expect do
          described_class.retriable(args.merge(max_interval: 1.5)) { increment_tries_with_exception }
        end.to raise_error(StandardError)

        expect(@next_interval_table).to eq(no_rand_timetable.merge(4 => 1.5, 5 => 1.5, 6 => nil))
      end

      it "obeys custom defined intervals" do
        interval_hash = no_rand_timetable.merge(4 => 1.5, 5 => 1.5, 6 => nil)
        intervals = interval_hash.values.compact.sort

        expect do
          described_class.retriable(on_retry: time_table_handler, intervals: intervals) do
            increment_tries_with_exception
          end
        end.to raise_error(StandardError)

        expect(@next_interval_table).to eq(interval_hash)
        expect(@tries).to eq(intervals.size + 1)
      end

      it "intervals option overrides tries, base_interval, max_interval, rand_factor, and multiplier" do
        # Even though we specify tries: 10, base_interval: 1.0, max_interval: 100.0,
        # rand_factor: 0.8, and multiplier: 2.0, the explicit intervals should take precedence
        custom_intervals = [0.1, 0.2, 0.3]

        expect do
          described_class.retriable(
            intervals: custom_intervals,
            tries: 10,
            base_interval: 1.0,
            max_interval: 100.0,
            rand_factor: 0.8,
            multiplier: 2.0,
            on_retry: time_table_handler,
          ) do
            increment_tries_with_exception
          end
        end.to raise_error(StandardError)

        # Should have 4 tries (3 intervals + 1), not 10
        expect(@tries).to eq(4)
        # Should use the exact intervals provided, not generate them
        expect(@next_interval_table[1]).to eq(0.1)
        expect(@next_interval_table[2]).to eq(0.2)
        expect(@next_interval_table[3]).to eq(0.3)
        expect(@next_interval_table[4]).to be_nil
      end
    end

    context "with an array :on parameter" do
      it "handles both kinds of exceptions" do
        described_class.retriable(on: [StandardError, NonStandardError]) do
          increment_tries

          raise StandardError if @tries == 1
          raise NonStandardError if @tries == 2
        end

        expect(@tries).to eq(3)
      end
    end

    context "with a Set :on parameter" do
      it "retries each exception class in the Set" do
        described_class.retriable(on: Set[StandardError, NonStandardError]) do
          increment_tries

          raise StandardError if @tries == 1
          raise NonStandardError if @tries == 2
        end

        expect(@tries).to eq(3)
      end
    end

    context "with a hash :on parameter" do
      let(:on_hash) { { NonStandardError => /NonStandardError occurred/ } }

      it "where the value is an exception message pattern" do
        expect do
          described_class.retriable(on: on_hash) { increment_tries_with_exception(NonStandardError) }
        end.to raise_error(NonStandardError, /NonStandardError occurred/)

        expect(@tries).to eq(3)
      end

      it "matches exception subclasses when message matches pattern" do
        expect do
          described_class.retriable(on: on_hash.merge(DifferentError => [/shouldn't happen/, /also not/])) do
            increment_tries_with_exception(SecondNonStandardError)
          end
        end.to raise_error(SecondNonStandardError, /SecondNonStandardError occurred/)

        expect(@tries).to eq(3)
      end

      it "does not retry matching exception subclass but not message" do
        expect do
          described_class.retriable(on: on_hash) do
            increment_tries
            raise SecondNonStandardError, "not a match"
          end
        end.to raise_error(SecondNonStandardError, /not a match/)

        expect(@tries).to eq(1)
      end

      it "does not call on_give_up when exception class matches but message does not" do
        callback_called = false

        expect do
          described_class.retriable(on: on_hash, on_give_up: proc { callback_called = true }) do
            increment_tries
            raise SecondNonStandardError, "not a match"
          end
        end.to raise_error(SecondNonStandardError, /not a match/)

        expect(callback_called).to be(false)
        expect(@tries).to eq(1)
      end

      it "successfully retries when the values are arrays of exception message patterns" do
        exceptions = []
        handler = ->(exception, try, _elapsed_time, _next_interval) { exceptions[try] = exception }
        on_hash = { StandardError => nil, NonStandardError => [/foo/, /bar/] }

        expect do
          described_class.retriable(tries: 4, on: on_hash, on_retry: handler) do
            increment_tries

            case @tries
            when 1
              raise NonStandardError, "foo"
            when 2
              raise NonStandardError, "bar"
            when 3
              raise StandardError
            else
              raise NonStandardError, "crash"
            end
          end
        end.to raise_error(NonStandardError, /crash/)

        expect(exceptions[1]).to be_a(NonStandardError)
        expect(exceptions[1].message).to eq("foo")
        expect(exceptions[2]).to be_a(NonStandardError)
        expect(exceptions[2].message).to eq("bar")
        expect(exceptions[3]).to be_a(StandardError)
      end
    end

    context "with a :retry_if parameter" do
      it "retries only when retry_if returns true" do
        described_class.retriable(tries: 3, retry_if: ->(_exception) { @tries < 3 }) do
          increment_tries
          raise StandardError, "StandardError occurred" if @tries < 3
        end

        expect(@tries).to eq(3)
      end

      it "does not retry when retry_if returns false" do
        expect do
          described_class.retriable(tries: 3, retry_if: ->(_exception) { false }) do
            increment_tries_with_exception
          end
        end.to raise_error(StandardError)

        expect(@tries).to eq(1)
      end

      it "can retry based on the wrapped exception cause" do
        root_cause_class = Class.new(StandardError)
        wrapper_class = Class.new(StandardError)

        described_class.retriable(
          on: [wrapper_class],
          tries: 3,
          retry_if: ->(exception) { exception.cause.is_a?(root_cause_class) },
        ) do
          increment_tries

          if @tries < 3
            begin
              raise root_cause_class, "root cause"
            rescue root_cause_class
              raise wrapper_class, "wrapped"
            end
          end
        end

        expect(@tries).to eq(3)
      end
    end

    it "runs for a max elapsed time of 2 seconds" do
      described_class.configure { |c| c.sleep_disabled = false }

      expect do
        described_class.retriable(base_interval: 1.0, multiplier: 1.0, rand_factor: 0.0, max_elapsed_time: 2.0) do
          increment_tries_with_exception
        end
      end.to raise_error(StandardError)

      expect(@tries).to eq(2)
    end

    it "does not count skipped sleep intervals against max elapsed time" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0)

      expect do
        described_class.retriable(tries: 3, base_interval: 1.0, rand_factor: 0.0, max_elapsed_time: 0.1) do
          increment_tries_with_exception
        end
      end.to raise_error(StandardError)

      expect(@tries).to eq(3)
    end

    it "retries up to tries limit when max_elapsed_time is nil" do
      expect do
        described_class.retriable(tries: 4, max_elapsed_time: nil) { increment_tries_with_exception }
      end.to raise_error(StandardError)

      expect(@tries).to eq(4)
    end

    it "uses monotonic clock for elapsed time tracking" do
      # Stub Process.clock_gettime to return controlled values so we can
      # verify elapsed_time passed to on_retry is derived from the monotonic clock.
      clock_calls = 0
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) do
        value = clock_calls.to_f
        clock_calls += 1
        value
      end

      elapsed_times = []
      on_retry = ->(_exception, _try, elapsed_time, _next_interval) { elapsed_times << elapsed_time }

      expect do
        described_class.retriable(tries: 3, on_retry: on_retry) { increment_tries_with_exception }
      end.to raise_error(StandardError)

      # start_time (call 0) + at least one elapsed_time computation per retry
      expect(clock_calls).to be >= 3
      # elapsed_time values should be positive and non-decreasing
      expect(elapsed_times).to all(be > 0)
      expect(elapsed_times).to eq(elapsed_times.sort)
    end

    it "raises ArgumentError on invalid options" do
      expect { described_class.retriable(does_not_exist: 123) { increment_tries } }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when tries is not a positive integer" do
      expect { described_class.retriable(tries: 1.5) { increment_tries } }
        .to raise_error(ArgumentError, /tries/)
    end

    it "raises ArgumentError when an interval is negative" do
      expect { described_class.retriable(intervals: [-1]) { increment_tries } }
        .to raise_error(ArgumentError, /intervals/)
    end

    it "raises ArgumentError when configured timing options become invalid" do
      described_class.configure { |config| config.tries = 0 }

      expect { described_class.retriable { increment_tries } }
        .to raise_error(ArgumentError, /tries/)
    end

    it "does not validate generated backoff options when intervals are provided" do
      described_class.retriable(intervals: [0], tries: 0, rand_factor: 1.1) { increment_tries }

      expect(@tries).to eq(1)
    end

    it "allows an empty interval array as one attempt" do
      expect do
        described_class.retriable(intervals: []) { increment_tries_with_exception }
      end.to raise_error(StandardError)

      expect(@tries).to eq(1)
    end

    it "rejects on: Object before invoking the block" do
      block_invoked = false

      expect do
        described_class.retriable(on: Object) { block_invoked = true }
      end.to raise_error(ArgumentError, /on must be an Exception class/)

      expect(block_invoked).to be(false)
    end
  end

  context "#configure" do
    it "exposes only the intended public API" do
      public_api_methods = %i[
        retriable
        with_context
        configure
        config
        with_override
      ]

      expect(described_class.singleton_methods(false)).to match_array(public_api_methods)
    end

    it "raises NoMethodError on invalid configuration" do
      expect { described_class.configure { |c| c.does_not_exist = 123 } }.to raise_error(NoMethodError)
    end
  end

  context "#retriable tries/intervals precedence" do
    it "lets a per-call tries clear globally configured intervals" do
      described_class.configure { |c| c.intervals = [0.5, 1.0] }

      expect do
        described_class.retriable(tries: 1) { increment_tries_with_exception }
      end.to raise_error(StandardError)

      expect(@tries).to eq(1)
    end

    it "still lets per-call intervals win when both intervals and tries are given" do
      expect do
        described_class.retriable(intervals: [0.5, 1.0], tries: 1) { increment_tries_with_exception }
      end.to raise_error(StandardError)

      expect(@tries).to eq(3) # intervals.size + 1
    end

    it "lets a with_context tries clear context intervals" do
      described_class.configure do |c|
        c.contexts[:api] = { intervals: [0.5, 1.0] }
      end

      expect do
        described_class.with_context(:api, tries: 1) { increment_tries_with_exception }
      end.to raise_error(StandardError)

      expect(@tries).to eq(1)
    end
  end

  context "#with_override" do
    it "takes precedence over both global config and local options" do
      described_class.configure { |c| c.tries = 2 }

      described_class.with_override(tries: 1) do
        expect { described_class.retriable(tries: 10) { increment_tries_with_exception } }.to raise_error(StandardError)
      end

      expect(@tries).to eq(1)
    end

    it "lets override tries take precedence over local intervals" do
      described_class.with_override(tries: 1) do
        expect do
          described_class.retriable(intervals: [0.5, 1.0]) { increment_tries_with_exception }
        end.to raise_error(StandardError)
      end

      expect(@tries).to eq(1)
    end

    it "lets override tries take precedence over context intervals" do
      described_class.configure do |c|
        c.contexts[:api] = { intervals: [0.5, 1.0] }
      end

      described_class.with_override(tries: 1) do
        expect { described_class.with_context(:api) { increment_tries_with_exception } }.to raise_error(StandardError)
      end

      expect(@tries).to eq(1)
    end

    it "lets override context tries take precedence over context intervals" do
      described_class.configure do |c|
        c.contexts[:api] = { intervals: [0.5, 1.0] }
      end

      described_class.with_override(contexts: { api: { tries: 1 } }) do
        expect { described_class.with_context(:api) { increment_tries_with_exception } }.to raise_error(StandardError)
      end

      expect(@tries).to eq(1)
    end

    it "replaces hash-valued options instead of deep-merging them" do
      described_class.with_override(on: { NonStandardError => nil }) do
        expect do
          described_class.retriable(on: { StandardError => nil }, tries: 2) { increment_tries_with_exception }
        end.to raise_error(StandardError)
      end

      expect(@tries).to eq(1)
    end

    it "can override local intervals with nil to use configured backoff" do
      described_class.configure { |c| c.tries = 3 }

      described_class.with_override(intervals: nil) do
        expect do
          described_class.retriable(intervals: [0.5, 1.0], on_retry: time_table_handler) do
            increment_tries_with_exception
          end
        end.to raise_error(StandardError)
      end

      expect(@tries).to eq(3)
      expect(@next_interval_table[1]).to be_between(0.0, 1.0)
    end

    it "applies override context values after with_context local options" do
      described_class.configure do |c|
        c.contexts[:api] = { tries: 3, base_interval: 1.0 }
      end

      described_class.with_override(contexts: { api: { tries: 1 } }) do
        described_class.with_context(:api, tries: 10) { increment_tries }
      end

      expect(@tries).to eq(1)
    end

    it "can define a context only in override config" do
      described_class.with_override(contexts: { test_only: { tries: 1 } }) do
        described_class.with_context(:test_only) { increment_tries }
      end

      expect(@tries).to eq(1)
    end

    it "does not apply context-only overrides to plain retriable calls" do
      described_class.with_override(contexts: { api: { tries: 1 } }) do
        expect { described_class.retriable(tries: 3) { increment_tries_with_exception } }.to raise_error(StandardError)
      end

      expect(@tries).to eq(3)
    end

    it "keeps configured context matchers when top-level override values apply" do
      described_class.configure do |c|
        c.contexts[:api] = { tries: 3, on: NonStandardError }
      end

      described_class.with_override(tries: 1) do
        expect { described_class.with_context(:api) { increment_tries_with_exception(NonStandardError) } }
          .to raise_error(NonStandardError)
      end

      expect(@tries).to eq(1)
    end

    it "combines local options with override-only contexts" do
      described_class.with_override(contexts: { api: { tries: 1 } }) do
        expect do
          described_class.with_context(:api, on: NonStandardError) do
            increment_tries_with_exception(NonStandardError)
          end
        end.to raise_error(NonStandardError)
      end

      expect(@tries).to eq(1)
    end

    it "reuses configured contexts when override does not include contexts" do
      described_class.configure do |c|
        c.contexts[:api] = { tries: 1 }
      end

      described_class.with_override(tries: 1) do
        described_class.with_context(:api) { increment_tries }
      end

      expect(@tries).to eq(1)
    end

    it "treats non-hash configured contexts as empty when override contexts are hash" do
      described_class.configure { |c| c.contexts = nil }

      described_class.with_override(contexts: { api: { tries: 1 } }) do
        described_class.with_context(:api) { increment_tries }
      end

      expect(@tries).to eq(1)
    ensure
      described_class.configure { |c| c.contexts = {} }
    end

    it "ignores nil override contexts values in with_context" do
      described_class.configure do |c|
        c.contexts[:api] = { tries: 1 }
      end

      described_class.with_override(contexts: nil) do
        described_class.with_context(:api) { increment_tries }
      end

      expect(@tries).to eq(1)
    end

    it "raises ArgumentError on non-hash override contexts values" do
      block_called = false

      expect { described_class.with_override(contexts: 123) { block_called = true } }
        .to raise_error(ArgumentError, /contexts must be a Hash or nil/)
      expect(block_called).to be(false)
    end

    it "raises ArgumentError on non-hash per-context override values" do
      block_called = false

      expect { described_class.with_override(contexts: { api: 123 }) { block_called = true } }
        .to raise_error(ArgumentError, /contexts\[:api\] must be a Hash/)
      expect(block_called).to be(false)
    end

    it "preserves outer override after rejected nested override contexts values" do
      described_class.with_override(tries: 2) do
        expect { described_class.with_override(tries: 1, contexts: 123) { :noop } }
          .to raise_error(ArgumentError, /contexts must be a Hash or nil/)

        expect { described_class.retriable(tries: 10) { increment_tries_with_exception } }
          .to raise_error(StandardError)
      end

      expect(@tries).to eq(2)
    end

    it "preserves outer context override after rejected nested per-context values" do
      described_class.configure do |c|
        c.contexts[:api] = { tries: 10 }
      end

      described_class.with_override(contexts: { api: { tries: 2 } }) do
        expect { described_class.with_override(contexts: { api: 123 }) { :noop } }
          .to raise_error(ArgumentError, /contexts\[:api\] must be a Hash/)

        expect { described_class.with_context(:api) { increment_tries_with_exception } }
          .to raise_error(StandardError)
      end

      expect(@tries).to eq(2)
    end

    it "shows merged context keys in with_context missing-context errors" do
      described_class.configure do |c|
        c.contexts[:configured] = { tries: 2 }
      end

      described_class.with_override(contexts: { override_only: { tries: 1 } }) do
        expect { described_class.with_context(:missing) { increment_tries } }
          .to raise_error(ArgumentError, /override_only/)
      end
    end

    it "does not snapshot configured contexts when adding override-only contexts" do
      described_class.configure do |c|
        c.contexts[:api] = { tries: 2 }
      end

      described_class.with_override(contexts: { test_only: { tries: 1 } }) do
        described_class.configure do |c|
          c.contexts[:api] = { tries: 5 }
        end

        expect { described_class.with_context(:api) { increment_tries_with_exception } }.to raise_error(StandardError)
      end

      expect(@tries).to eq(5)
    end

    it "raises ArgumentError on invalid override options" do
      expect { described_class.with_override(does_not_exist: 123) { :noop } }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError on empty override options" do
      expect { described_class.with_override({}) { :noop } }.to raise_error(ArgumentError, /empty override/)
    end

    it "raises ArgumentError when called without a block" do
      expect { described_class.with_override(tries: 1) }.to raise_error(ArgumentError, /requires a block/)
    end

    it "raises ArgumentError on invalid context override options" do
      expect { described_class.with_override(contexts: { api: { does_not_exist: 123 } }) { :noop } }
        .to raise_error(ArgumentError, /does_not_exist is not a valid option/)
    end

    it "clears the override after the block returns" do
      described_class.with_override(tries: 1) do
        # active here
      end

      expect { described_class.retriable(tries: 3) { increment_tries_with_exception } }.to raise_error(StandardError)
      expect(@tries).to eq(3)
    end

    it "clears the override when the block raises" do
      expect do
        described_class.with_override(tries: 1) { raise "boom" }
      end.to raise_error(RuntimeError, "boom")

      expect { described_class.retriable(tries: 3) { increment_tries_with_exception } }.to raise_error(StandardError)
      expect(@tries).to eq(3)
    end

    it "returns the block's return value" do
      result = described_class.with_override(tries: 1) { :return_value }
      expect(result).to eq(:return_value)
    end

    it "restores the outer override when nested blocks exit" do
      tries_seen = []
      handler = ->(_exception, try, _elapsed, _next) { tries_seen << [Thread.current.object_id, try] }

      described_class.with_override(tries: 2, on_retry: handler) do
        described_class.with_override(tries: 4, on_retry: handler) do
          expect { described_class.retriable { increment_tries_with_exception } }.to raise_error(StandardError)
        end

        # After the inner block exits, the outer tries: 2 override is restored.
        @tries = 0
        expect { described_class.retriable { increment_tries_with_exception } }.to raise_error(StandardError)
        expect(@tries).to eq(2)
      end
    end
  end

  context "#with_override thread safety" do
    # Coordinate threads with queues rather than sleep so tests are deterministic.
    # sleep_disabled is already set to true in the top-level before(:each), so
    # retriable calls do not actually sleep between attempts.

    it "isolates overrides between threads" do
      ready = Queue.new
      proceed = Queue.new
      results = {}
      mutex = Mutex.new

      threads = [1, 2].map do |id|
        Thread.new do
          described_class.with_override(tries: id) do
            ready << true
            proceed.pop
            tries = 0
            begin
              described_class.retriable do
                tries += 1
                raise StandardError
              end
            rescue StandardError
              mutex.synchronize { results[id] = tries }
            end
          end
        end
      end

      2.times { ready.pop }
      2.times { proceed << true }
      threads.each(&:join)

      expect(results).to eq(1 => 1, 2 => 2)
    end

    it "does not leak an active override into a sibling thread" do
      override_active = Queue.new
      sibling_done = Queue.new
      sibling_tries = nil

      setter = Thread.new do
        described_class.with_override(tries: 1) do
          override_active << true
          sibling_done.pop
        end
      end

      sibling = Thread.new do
        override_active.pop
        tries = 0
        begin
          described_class.retriable(tries: 3) do
            tries += 1
            raise StandardError
          end
        rescue StandardError
          sibling_tries = tries
        end
        sibling_done << true
      end

      [setter, sibling].each(&:join)
      expect(sibling_tries).to eq(3)
    end

    it "does not propagate an active override to a child thread" do
      child_tries = nil

      described_class.with_override(tries: 1) do
        Thread.new do
          tries = 0
          begin
            described_class.retriable(tries: 3) do
              tries += 1
              raise StandardError
            end
          rescue StandardError
            child_tries = tries
          end
        end.join
      end

      expect(child_tries).to eq(3)
    end

    it "shares the active override with fibers in the same thread" do
      fiber_tries = nil

      Thread.new do
        described_class.with_override(tries: 1) do
          Fiber.new do
            tries = 0
            begin
              described_class.retriable(tries: 10) do
                tries += 1
                raise StandardError
              end
            rescue StandardError
              fiber_tries = tries
            end
          end.resume
        end
      end.join

      expect(fiber_tries).to eq(1)
    end

    it "does not treat a main-thread override as a global default for other threads" do
      other_thread_tries = nil

      described_class.with_override(tries: 1) do
        Thread.new do
          tries = 0
          begin
            described_class.retriable(tries: 3) do
              tries += 1
              raise StandardError
            end
          rescue StandardError
            other_thread_tries = tries
          end
        end.join
      end

      expect(other_thread_tries).to eq(3)
    end

    it "applies overridden on_give_up handlers" do
      callback_called = false

      expect do
        described_class.with_override(on_give_up: proc { callback_called = true }) do
          described_class.retriable(tries: 1) { increment_tries_with_exception }
        end
      end.to raise_error(StandardError)

      expect(callback_called).to be(true)
    end

    it "applies on_give_up handlers configured via per-context overrides" do
      received_reason = nil
      handler = proc { |_e, _try, _elapsed, _interval, reason| received_reason = reason }

      expect do
        described_class.with_override(contexts: { api: { tries: 1, on_give_up: handler } }) do
          described_class.with_context(:api) { increment_tries_with_exception }
        end
      end.to raise_error(StandardError)

      expect(received_reason).to eq(:tries_exhausted)
    end
  end

  context "#with_context" do
    let(:api_tries) { 4 }

    before do
      described_class.configure do |c|
        c.contexts[:sql] = { tries: 1 }
        c.contexts[:api] = { tries: api_tries }
      end
    end

    it "stops at first try if the block does not raise an exception" do
      described_class.with_context(:sql) { increment_tries }
      expect(@tries).to eq(1)
    end

    it "raises an ArgumentError when called without a block" do
      expect { described_class.with_context(:sql) }
        .to raise_error(ArgumentError, /with_context requires a block/)
      expect(@tries).to eq(0)
    end

    it "checks for a block before looking up the context" do
      expect { described_class.with_context(:missing) }
        .to raise_error(ArgumentError, /with_context requires a block/)
      expect(@tries).to eq(0)
    end

    it "passes try count through to the context block" do
      seen_tries = []

      described_class.with_context(:api) do |try|
        seen_tries << try
        raise StandardError if try < 3
      end

      expect(seen_tries).to eq([1, 2, 3])
    end

    it "respects the context options" do
      expect { described_class.with_context(:api) { increment_tries_with_exception } }.to raise_error(StandardError)
      expect(@tries).to eq(api_tries)
    end

    it "allows override options" do
      expect do
        described_class.with_context(:sql, tries: 5) { increment_tries_with_exception }
      end.to raise_error(StandardError)

      expect(@tries).to eq(5)
    end

    it "raises an ArgumentError when the context isn't found" do
      expect { described_class.with_context(:wtf) { increment_tries } }.to raise_error(ArgumentError, /wtf not found/)
    end

    it "treats non-Hash context values as empty options" do
      described_class.configure do |c|
        c.contexts[:broken] = nil
      end

      described_class.with_context(:broken) { increment_tries }
      expect(@tries).to eq(1)
    end

    it "surfaces an invalid context on any retriable call before that context is used" do
      described_class.configure { |c| c.contexts[:unused] = { contexts: {} } }

      expect { described_class.retriable { :ok } }
        .to raise_error(ArgumentError, /contexts is not a valid option/)
    end

    it "invokes on_give_up configured on a context" do
      callback_called = false
      described_class.configure do |c|
        c.contexts[:flaky] = { tries: 1, on_give_up: proc { callback_called = true } }
      end

      expect { described_class.with_context(:flaky) { increment_tries_with_exception } }
        .to raise_error(StandardError)

      expect(callback_called).to be(true)
    end
  end
end
