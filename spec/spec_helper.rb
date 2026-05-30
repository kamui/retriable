# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  minimum_coverage 95
end

require "pry"
require_relative "../lib/retriable"
require_relative "support/exceptions"

RSpec.configure do |config|
  config.before(:each) do
    srand(0)
  end
end
