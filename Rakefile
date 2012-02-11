# encoding: utf-8

require 'bundler'
Bundler::GemHelper.install_tasks

require 'rake/testtask'
task :default => :test

desc "Run tests"
task :test do
  Rake::TestTask.new do |t|
    t.libs << 'lib' << 'test'
    t.pattern = 'test/**/*_test.rb'
    t.verbose = true
  end
end