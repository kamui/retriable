# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'retriable_environments/version'
require 'retriable/version'

Gem::Specification.new do |spec|
  spec.name          = 'retriable_environments'
  spec.version       = RetriableEnvironments::VERSION
  spec.authors       = ['Lumos Labs, Inc.']
  spec.email         = ['analytics@lumoslabs.com']
  spec.summary       = %q{Environments feature for Retriable gem}
  spec.description   = %q{Environments feature for Retriable gem}
  spec.homepage      = %q{http://github.com/kamui/retriable}
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z | grep retriable_environments`.split("\x0")
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.0.0'

  spec.add_dependency 'retriable', Retriable::VERSION
end
