require 'retriable'
require 'minitest/autorun'

class RetriableTest < Minitest::Test
  def test_raise_no_block
    assert_raises LocalJumpError do
      Retriable.retriable :on => StandardError
    end
  end

  def test_without_arguments
    i = 0

    Retriable.retriable do
      i += 1
      raise StandardError.new
    end
    rescue StandardError
    assert_equal 3, i
  end

  def test_with_one_exception_and_two_tries
    i = 0

    Retriable.retriable :on => EOFError, :tries => 2 do
      i += 1
      raise EOFError.new
    end

    rescue EOFError
    assert_equal i, 2
  end

  def test_with_arguments
    i = 0

    on_retry = Proc.new do |exception, tries|
      assert_equal exception.class, ArgumentError
      assert_equal i, tries
    end

    Retriable.retriable :on => [EOFError, ArgumentError], :on_retry => on_retry, :tries => 5, :sleep => 0.2 do |h|
      i += 1
      raise ArgumentError.new
    end

  rescue ArgumentError
    assert_equal 5, i
  end

  def test_with_interval_proc
    was_called = false

    sleeper = Proc.new do |attempts|
      was_called = true
      attempts
    end

    Retriable.retriable :on => EOFError, :interval => sleeper do |h|
      raise EOFError.new
    end
    rescue
    assert_equal was_called, true
  end

  def test_kernel_ext
    assert_raises NoMethodError do
      retriable do
        puts 'should raise NoMethodError'
      end
    end

    require 'retriable/core_ext/kernel'
    i = 0

    retriable do
      i += 1
      raise StandardError.new
    end

    rescue StandardError
    assert_equal 3, i
  end
end
