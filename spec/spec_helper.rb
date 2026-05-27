# frozen_string_literal: true

require "simplecov"
SimpleCov.start

require "pry"
require_relative "../lib/retriable"
require_relative "support/exceptions"

RSpec.configure do |config|
  config.before(:each) do
    srand(0)
    Retriable::Config.timeout_deprecation_warned = false
  end
end
