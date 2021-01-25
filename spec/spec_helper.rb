require 'simplecov'
SimpleCov.start

require 'pry'
require_relative '../lib/retriable'
require_relative 'support/exceptions.rb'

RSpec.configure do |config|
  config.before(:each) do
    srand(0)
  end
end
