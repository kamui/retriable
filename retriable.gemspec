# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "retriable/version"

Gem::Specification.new do |spec|
  spec.name          = "retriable"
  spec.version       = Retriable::VERSION
  spec.authors       = ["Jack Chu"]
  spec.email         = ["jack@jackchu.com"]
  spec.summary       = "Retriable is a simple DSL to retry failed code blocks with randomized exponential backoff"
  spec.description   = "Retriable is a simple DSL to retry failed code blocks with randomized " \
                       "exponential backoff. This is especially useful when interacting with external " \
                       "APIs/services or file system calls."
  spec.homepage      = "https://github.com/kamui/retriable"
  spec.license       = "MIT"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.2"
end
