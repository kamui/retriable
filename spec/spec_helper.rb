# frozen_string_literal: true

require "simplecov"
SimpleCov.start

require "pry"
require_relative "../lib/retriable"
require_relative "support/exceptions"

# Make Retriable's deprecation notices observable to RSpec's
# `output().to_stderr` matcher. On Ruby 3.0+ the `:deprecated` warning category
# is suppressed by default, which would hide the notices we want to assert on.
Warning[:deprecated] = true if Warning.respond_to?(:[])

# Used by deprecation specs that only make sense on Rubies where `Kernel#warn`
# supports the `category:` keyword (added in Ruby 2.7).
WARN_CATEGORY_SUPPORTED = Warning.respond_to?(:[]) &&
                          Kernel.method(:warn).parameters.include?(%i[key category])

RSpec.configure do |config|
  config.before(:each) do
    srand(0)
    Retriable::Config.timeout_deprecation_warned = false
    Warning[:deprecated] = true if Warning.respond_to?(:[])
  end
end
