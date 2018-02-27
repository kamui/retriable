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
require_relative "support/exceptions.rb"

class TryRecorder
  attr_accessor :tries

  def initialize
    @tries = 0
  end
end

RSpec.configure do |config|
  config.before(:each) do
    srand(0)
  end
end
