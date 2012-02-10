# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "retryable-rb/version"

Gem::Specification.new do |s|
  s.name        = "retryable-rb"
  s.version     = RetryableRb::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Robert Sosinski", "Jack Chu"]
  s.email       = ["email@robertsosinski.com", "jack@jackchu.com"]
  s.homepage = %q{http://github.com/robertsosinski/retryable}
  s.summary = %q{Easy to use DSL to retry code if an exception is raised.}
  s.description = %q{Easy to use DSL to retry code if an exception is raised.}

  s.rubyforge_project = "retryable-rb"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
