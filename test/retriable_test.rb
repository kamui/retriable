require 'retriable'
require 'minitest/autorun'
require 'rr'

class TestError < StandardError; end
class AnotherTestError < StandardError; end

class RetriableTest < Minitest::Test
  def test_no_block_given
    assert_raises LocalJumpError do
      Retriable.retriable on: StandardError
    end
  end

  def test_no_retries
    called = 0

    Retriable.retriable on: TestError, tries: 0 do
      called += 1
      raise TestError
    end
  rescue TestError
    assert_equal 1, called, 'Should have been called once (before exception) with no retries'
  end

  def test_one_retry
    called = 0

    Retriable.retriable on: TestError, tries: 1 do
      called += 1
      raise TestError
    end
  rescue TestError
    assert_equal 2, called, 'Should have been called twice (before exception + retry) `tries == 1`'
  end

  def test_default_options
    called = 0

    Retriable.retriable do
      called += 1
      raise TestError
    end
  rescue TestError
    assert_equal 4, called, 'Should have been called 4 times (before exception + 3 retries) with default `tries == 3`'
  end

  def test_errors_list
    called = 0

    Retriable.retriable on: [AnotherTestError, TestError], tries: 1 do |h|
      called += 1
      raise AnotherTestError
    end
  rescue AnotherTestError
    assert_equal 2, called, 'Should have retried from an error from the list supplied'
  end

  def test_error_callback
    called = 0

    on_retry = Proc.new do |exception, attempts|
      assert_equal exception.class, TestError, 'Exception supplied to callback is not the one which had been raised'
      assert_equal called, attempts, 'Incorrect number of attempts is supplied in callback'
    end

    Retriable.retriable on: TestError, on_retry: on_retry, tries: 1 do |h|
      called += 1
      raise TestError
    end
  rescue TestError
  end

  def test_custom_interval
    interval = 0

    Object.stub(:sleep, 0.2) { interval = 0.2 }

    Retriable.retriable on: TestError, tries: 1, interval: 0.2 do |h|
      raise TestError
    end
  rescue TestError
    assert_equal 0.2, interval, 'Should have retried with the supplied interval'
  end

  def test_with_interval_proc
    attempt = 0
    was_called = false

    sleeper = Proc.new do |try|
      attempt = try
      was_called = true

      0
    end

    Retriable.retriable on: TestError, interval: sleeper, tries: 2 do |h|
      raise TestError
    end
  rescue TestError
    assert was_called, 'Interval callback has not been called'
    assert_equal 2, attempt, 'Interval callback should receive a current attempt number'
  end

  def test_interval_as_an_array
    sleep_lengths = []

    any_instance_of(Object) do |klass|
      stub(klass).sleep {|length| sleep_lengths << length  }
    end

    Retriable.retriable on: TestError, interval: [1, 2, 3] do |h|
      raise TestError
    end
  rescue TestError
    assert_equal [1, 2, 3], sleep_lengths, 'Should have slept for each length supplied'
  end

  def test_interval_as_an_array_with_number_of_tries_supplied
    called = 0

    Retriable.retriable on: TestError, interval: [0, 0, 0], tries: 2 do |h|
      called += 1
      raise TestError
    end
  rescue TestError
    assert_equal 3, called, 'Method should be retried as many times as `tries` supplied even if interval is an array'
  end

  def test_number_of_tries_greater_than_interval_items
    sleep_lengths = []
    called = 0

    any_instance_of(Object) do |klass|
      stub(klass).sleep {|length| sleep_lengths << length  }
    end

    Retriable.retriable on: TestError, interval: [1, 2], tries: 3 do |h|
      called += 1
      raise TestError
    end
  rescue TestError
    assert_equal 4, called
    assert_equal [1, 2, 1], sleep_lengths, 'Should cycle through the interval values if number of tries is greater than interval size'
  end

  def test_kernel_ext
    assert_raises NoMethodError do
      retriable do
        puts 'should raise NoMethodError'
      end
    end

    require 'retriable/core_ext/kernel'
    called = 0

    retriable do
      called += 1
      raise TestError
    end
  rescue TestError
    assert_equal 4, called
  end
end
