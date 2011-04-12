require 'rake'
require 'rake/testtask'
require 'echoe'

Rake::TestTask.new do |t|
  t.libs << "test"
end

Echoe.new("retryable-rb") do |p|
  p.author = "Robert Sosinski"
  p.email = "email@robertsosinski.com"
  p.url = "http://github.com/robertsosinski/retryable"
  p.description = p.summary = "Easy to use DSL to retry code if an exception is raised."
  p.runtime_dependencies = []
  p.development_dependencies = ["echoe >=4.3.1"]
end