require_relative "spec_helper"

describe Retriable::Wrapper do
  subject do
    Retriable::Wrapper
  end
  
  it 'returns the wrapped object via __setobj__' do
    item = :foo
    wrapped = subject.new(item)
    wrapped.must_be_kind_of subject
    unwrapped = wrapped.__getobj__
    unwrapped.must_be_kind_of Symbol
  end
  
  it 'supports setting retrying methods explicitly' do
    raising_class = Class.new do
      def self.perform_failing_operation
        @tries_failing ||= 0
        @tries_failing += 1
        raise StandardError.new if @tries_failing < 3
        "success"
      end
      
      def self.perform_non_retrying_operation
        @tries_non_retrying ||= 0
        @tries_non_retrying += 1
        raise StandardError.new if @tries_non_retrying < 2 
      end
    end
    
    wrapped_raising_class = subject.new(raising_class, methods: [:perform_failing_operation])
    wrapped_raising_class.perform_failing_operation.must_equal "success"
    
    expect do
      wrapped_raising_class.perform_non_retrying_operation
    end.must_raise StandardError
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
