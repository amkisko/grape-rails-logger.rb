# Main entry point for grape-rails-logger gem
# Following RubyGems naming convention: gem name grape-rails-logger -> require 'grape/rails/logger'
require_relative "../../grape_rails_logger"

# Define Grape::Rails::Logger as an alias to GrapeRailsLogger for convention compliance
# This allows the gem to be auto-loaded by Bundler without explicit require
module Grape
  module Rails
    Logger = GrapeRailsLogger
  end
end
