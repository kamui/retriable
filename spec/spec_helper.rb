require "codeclimate-test-reporter"
require "simplecov"

CodeClimate::TestReporter.configure do |config|
  config.logger.level = Logger::WARN
end

SimpleCov.start do
  formatter SimpleCov::Formatter::MultiFormatter[
    SimpleCov::Formatter::HTMLFormatter,
    CodeClimate::TestReporter::Formatter
  ]
  add_filter 'spec/'
end

require "minitest/autorun"
require "minitest/focus"
require "awesome_print"
require "pry"

require_relative "../lib/retriable"
