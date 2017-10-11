require_relative "spec_helper"

describe Retriable do
  let(:klass) do
    Class.new do
      extend Retriable::Ext
      attr_accessor :tries

      def initialize
        @tries ||= 0
      end

      def hi(name, fail: nil)
        @tries += 1
        if fail.nil?
          "Hi, #{name}"
        else
          raise fail
        end
      end

      def bye(fail: nil)
        @tries += 1
        if fail.nil? || @tries > 3
          yield @tries
        else
          raise fail
        end
      end
    end
  end

  subject { klass.new }

  it 'makes methods retryable' do
    klass.retriable(:hi, sleep_disabled: true)
    assert_raises do
      subject.hi("Robot", fail: "Beep!")
    end
    expect(subject.tries).must_equal 3
  end

  it 'passes along method args' do
    expect(subject.hi("Robot")).must_equal "Hi, Robot"
  end

  it 'passes along method block' do
    klass.retriable(:bye, sleep_disabled: true)
    expect(subject.bye { |n| "Called #{n} times" }).must_equal "Called 1 times"
  end

  it 'retries methods with blocks' do
    klass.retriable(:bye, sleep_disabled: true, tries: 5)
    last_result = subject.bye(fail: "Beep!") { |n| "Called #{n} times, before succeeding finally!" }
    expect(subject.tries).must_equal 4
    expect(last_result).must_equal "Called 4 times, before succeeding finally!"
  end

  it 'passes along retriable options' do
    klass.retriable(:hi, sleep_disabled: true, on: { RuntimeError => /Boop/ })
    assert_raises do
      subject.hi("Robot", fail: "Beep")
    end
    expect(subject.tries).must_equal 1
    subject.tries = 0
    assert_raises do
      subject.hi("Robot", fail: "Boop")
    end
    expect(subject.tries).must_equal 3
  end
end
