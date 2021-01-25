require 'bundler/setup'
Bundler.require(:test, :development)

begin
  require 'rspec/core/rake_task'
  require 'rubocop/rake_task'
rescue LoadError => e
  require 'shellwords'
  raise "Required gem #{e.path.inspect} not found. " \
                      'Be sure you ran `bundle install` and are launching rake via ' \
                      "`bundle exec rake #{ARGV.shelljoin}`."
end

namespace :test do
  RSpec::Core::RakeTask.new(:rspec) do |t|
    t.rspec_opts = '-w --backtrace --no-fail-fast'
  end

  RuboCop::RakeTask.new('rubocop') do |t, _task_args|
    t.options << '--require' << 'rubocop-rspec'
    t.options << '--fail-level' << 'convention'
    t.options << '--display-cop-names'
    t.options << '--extra-details'
    t.options << '--display-style-guide'
    # Can't enable parallel because it will break rubocop:autocorrect
    # t.options << '--parallel'
  end

  desc 'Run all tests'
  task all: %w[test:rubocop test:rspec]

  task ci: %w[test:all]
end

desc 'Alias for test:all'
task test: %w[test:all]

task default: %w[test]
