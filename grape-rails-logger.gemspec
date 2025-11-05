require_relative "lib/grape_rails_logger/version"

Gem::Specification.new do |spec|
  spec.name          = "grape-rails-logger"
  spec.version       = GrapeRailsLogger::VERSION
  spec.authors       = ["amkisko"]
  spec.email         = ["contact@kiskolabs.com"]

  spec.summary       = "Unified JSON request logging for Grape on Rails with DB timing."
  spec.description   = "Rails-compatible, ActiveSupport-integrated logging for Grape APIs, including request context and ActiveRecord timings."
  spec.homepage      = "https://github.com/amkisko/grape-rails-logger.rb"
  spec.license       = "MIT"

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "sig/**/*", "README.md", "LICENSE*", "CHANGELOG.md"].select { |f| File.file?(f) }
  end
  spec.required_ruby_version = ">= 2.7"

  spec.metadata = {
    "source_code_uri" => "https://github.com/amkisko/grape-rails-logger.rb",
    "changelog_uri" => "https://github.com/amkisko/grape-rails-logger.rb/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/amkisko/grape-rails-logger.rb/issues"
  }

  spec.add_runtime_dependency "activesupport", ">= 6.0", "< 9.0"
  spec.add_runtime_dependency "railties", ">= 6.0", "< 9.0"
  spec.add_runtime_dependency "grape", ">= 1.6", "< 3.0"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "simplecov", "~> 0.21"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.6"
  spec.add_development_dependency "simplecov-cobertura", "~> 3"
  spec.add_development_dependency "standard", "~> 1.0"
  spec.add_development_dependency "appraisal", "~> 2.4"
  spec.add_development_dependency "memory_profiler", "~> 1.0"
  spec.add_development_dependency "rbs", "~> 3.0"
end

