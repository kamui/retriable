# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{retryable-rb}
  s.version = "1.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["Robert Sosinski"]
  s.date = %q{2011-04-17}
  s.description = %q{Easy to use DSL to retry code if an exception is raised.}
  s.email = %q{email@robertsosinski.com}
  s.extra_rdoc_files = ["CHANGELOG", "LICENSE", "README.markdown", "lib/retryable.rb"]
  s.files = ["CHANGELOG", "LICENSE", "Manifest", "README.markdown", "Rakefile", "lib/retryable.rb", "retryable-rb.gemspec", "test/retryable_test.rb"]
  s.homepage = %q{http://github.com/robertsosinski/retryable}
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Retryable-rb", "--main", "README.markdown"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{retryable-rb}
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Easy to use DSL to retry code if an exception is raised.}
  s.test_files = ["test/retryable_test.rb"]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<echoe>, [">= 4.3.1"])
    else
      s.add_dependency(%q<echoe>, [">= 4.3.1"])
    end
  else
    s.add_dependency(%q<echoe>, [">= 4.3.1"])
  end
end
