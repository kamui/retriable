# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :test do
  gem "rspec", "~> 3.0"
  gem "simplecov", require: false
end

group :development do
  gem "listen", "~> 3.1"
  gem "rubocop", "~> 1.86"
end

group :development, :test do
  gem "pry"
  gem "rake", "~> 13.0"
end
