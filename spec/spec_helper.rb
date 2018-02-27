require "codeclimate-test-reporter"
require "simplecov"

CodeClimate::TestReporter.configure do |config|
  config.logger.level = Logger::WARN
end

SimpleCov.start

require "minitest/autorun"
require "minitest/focus"
require "pry"

require_relative "../lib/retriable"

RSpec.configure do |config|
  config.before(:each) do
    srand(0)
  end
end
