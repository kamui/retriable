# encoding: utf-8

require 'retriable'
require 'minitest/autorun'

class RetriableTest < MiniTest::Unit::TestCase
  def test_without_arguments
    i = 0

    retriable do
      i += 1
      raise StandardError.new
    end
  rescue StandardError
    assert_equal 3, i
  end

  def test_with_one_exception_and_two_tries
    i = 0

    retriable :on => EOFError, :tries => 2 do
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

    retriable :on => [EOFError, ArgumentError], :on_retry => on_retry, :tries => 5, :sleep => 0.2 do |h|
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

    retriable :on => EOFError, :interval => sleeper do |h|
      raise EOFError.new
    end
  rescue
    assert_equal was_called, true
  end
end
