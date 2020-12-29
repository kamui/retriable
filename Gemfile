# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :test do
  gem "rspec"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", ">= 0.50", "< 0.51", require: false
  gem "rubocop-rspec", require: false
end

group :development, :test do
  gem "pry"
end
