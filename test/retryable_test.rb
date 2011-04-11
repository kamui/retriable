$:.unshift(File.dirname(__FILE__) + "../lib")

require 'test/unit'
require 'retryable'

class RetryableTest < Test::Unit::TestCase
  def test_without_arguments
    i = 0
    
    Retryable.retryable do
      i += 1
      
      raise Exception.new
    end
  rescue Exception
    assert_equal i, 2
  end
  
  def test_with_one_exception_and_two_times
    i = 0
    
    Retryable.retryable :on => EOFError, :times => 2 do
      i += 1
      
      raise EOFError.new
    end
  
  rescue EOFError
    assert_equal i, 3
  end
  
  def test_with_arguments_and_handler
      i = 0
      
      then_cb    = Proc.new do |e, h, a, r, t|
        assert_equal e.class, ArgumentError
        assert h[:value]
        
        assert_equal a, i
        assert_equal r, 6 - a
        assert_equal t, 5
      end
      
      finally_cb = Proc.new do |e, h, a, r, t|
        assert_equal e.class, ArgumentError
        assert h[:value]
        
        assert_equal a, 6
        assert_equal r, 0
        assert_equal t, 5
      end
      
      always_cb  = Proc.new do |h, a, r, t|
        assert h[:value]
        
        assert_equal a, 6
        assert_equal r, 0
        assert_equal t, 5
      end
      
      Retryable.retryable :on => [EOFError, ArgumentError], :then => then_cb, :finally => finally_cb, :always => always_cb, :times => 5, :sleep => 0.2 do |h|
        i += 1
        
        h[:value] = true
        
        raise ArgumentError.new
      end
      
    rescue ArgumentError
      assert_equal i, 6
    end
end