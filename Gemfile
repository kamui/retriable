# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :test do
  gem "rspec", "~> 3.0"
  gem "simplecov", require: false
end

group :development do
  gem "bundler-audit", "~> 0.9"
  gem "listen", "~> 3.1"
  gem "rbs", "~> 3.0", platforms: :ruby
  gem "rubocop", "~> 1.86"
end

group :development, :test do
  gem "pry"
  gem "rake", "~> 13.0"
end
