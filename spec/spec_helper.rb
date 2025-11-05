require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter { |source_file| source_file.lines.count < 5 }
end

require "simplecov-cobertura"
SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter

require "bundler/setup"
require "climate_control"
require "active_support"
require "active_support/core_ext/string/inquiry"
require "active_support/core_ext/object/try"
require "active_support/notifications"
require "grape"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require_relative f }

require "grape_rails_logger"

# Note: ActiveSupport::Configurable deprecation warning may appear from Grape dependency
# This is expected and comes from third-party code, not this gem

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
