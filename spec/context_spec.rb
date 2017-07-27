require_relative "spec_helper"

class TestError < Exception; end

describe "Retriable Context" do
  subject do
    Retriable
  end

  before do
    require_relative "../lib/retriable/context"
    srand 0
  end

  describe "with context and sleep disabled" do
    before do
      Retriable.configure do |c, context|
        c.sleep_disabled = true
        context[:sql] = { tries: 1 }
        context[:api] = { tries: 3 }
      end
    end

    it "sql context stops at first try if the block does not raise an exception" do
      tries = 0
      subject.with_context(:sql) do
        tries += 1
      end

      expect(tries).must_equal 1
    end

    it "with_context respects the context options" do
      tries = 0

      expect do
        subject.with_context(:api) do
          tries += 1
          raise StandardError.new, "StandardError occurred"
        end
      end.must_raise StandardError

      expect(tries).must_equal 3
    end

    it "with_context allows override options" do
      tries = 0

      expect do
        subject.with_context(:sql, tries: 5) do
          tries += 1
          raise StandardError.new, "StandardError occurred"
        end
      end.must_raise StandardError

      expect(tries).must_equal 5
    end

    it "raises an ArgumentError when the context isn't found" do
      tries = 0

      expect do
        subject.with_context(:wtf) do
          tries += 1
        end
      end.must_raise ArgumentError
    end
  end
end
