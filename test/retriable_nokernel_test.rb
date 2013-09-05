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
end