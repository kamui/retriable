require "minitest/autorun"
require "minitest/focus"

if defined?(CodeClimate)
  CodeClimate::TestReporter.configure do |config|
    config.logger.level = Logger::WARN
  end

  SimpleCov.start do
    formatter SimpleCov::Formatter::MultiFormatter[
      SimpleCov::Formatter::HTMLFormatter,
      CodeClimate::TestReporter::Formatter
    ]
  end
elsif defined?(SimpleCov)
  SimpleCov.start
end

require_relative "../lib/retriable"
