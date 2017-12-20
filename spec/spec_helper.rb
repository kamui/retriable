require "simplecov"
require "codeclimate-test-reporter"

CodeClimate::TestReporter.configure do |config|
  config.logger.level = Logger::WARN
end

SimpleCov.start

require "minitest/autorun"
require "minitest/spec"
require "minitest/focus"
require "pry"

require_relative "../lib/retriable"
