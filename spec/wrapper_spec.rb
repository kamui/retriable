require_relative "spec_helper"

describe Retriable::Wrapper do
  subject do
    Retriable::Wrapper
  end
  
  it "makes 3 tries when retrying block of code raising StandardError with no arguments" do
    $tries = 0
    
    raising_class = Class.new do
      def self.perform_failing_operation
        $tries += 1
        raise StandardError.new
      end
    end
    
    expect do
      wrapped_raising_class = subject.new(raising_class, {})
      wrapped_raising_class.perform_failing_operation
    end.must_raise StandardError
    
    expect($tries).must_equal 3
  end
end
