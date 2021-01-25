# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :test do
  gem 'rspec'
  gem 'simplecov', require: false
end

group :development, :test do
  gem 'rubocop', '>= 0.50', '< 0.51', require: false
  gem 'rubocop-rspec', require: false
end

group :development, :test do
  gem 'jazz_fingers'
  gem 'rake'
  # byebug constraint due to lack of support for binding.local_variables
  # in ruby 2.0
  gem 'byebug', '< 9.0.0'
  # pry constraints fix https://github.com/pry/pry/issues/2121
  gem 'pry', '!= 0.13.0', '!= 0.13.1'
end
