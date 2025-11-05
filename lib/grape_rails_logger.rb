require "active_support"
require "active_support/notifications"
require "grape"

# Load all required files first to ensure constants are available
# This must happen before the module definition (like other gems do)
require_relative "grape_rails_logger/version"
require_relative "grape_rails_logger/grape_instrumentation"
require_relative "grape_rails_logger/endpoint_wrapper"
require_relative "grape_rails_logger/debug_tracer"

module GrapeRailsLogger
  # Configuration for GrapeRailsLogger
  #
  # When running in Rails, use Rails.application.config.grape_rails_logger instead:
  #
  # @example Configure in Rails initializer
  #   # config/initializers/grape_rails_logger.rb
  #   Rails.application.config.grape_rails_logger.enabled = true
  #   Rails.application.config.grape_rails_logger.subscriber_class = CustomSubscriber
  #
  # @example Standalone usage (non-Rails)
  #   GrapeRailsLogger.config.enabled = false
  class Config
    attr_accessor :enabled, :subscriber_class, :logger, :tag

    def initialize
      @enabled = true
      @subscriber_class = GrapeRequestLogSubscriber
      @logger = nil # Default to nil, will use Rails.logger if available
      @tag = "Grape" # Default tag for TaggedLogging
    end
  end

  # Global configuration instance (for non-Rails usage)
  #
  # @return [Config] The configuration object
  def self.config
    @config ||= Config.new
  end

  # Configure the logger (for non-Rails usage)
  #
  # @yield [config] Yields the configuration object
  # @example
  #   GrapeRailsLogger.configure do |config|
  #     config.enabled = false
  #   end
  def self.configure
    yield config
  end

  # Get the effective configuration (Rails-aware)
  #
  # @return [Config] The active configuration object
  def self.effective_config
    if defined?(Rails) && Rails.application && Rails.application.config.respond_to?(:grape_rails_logger)
      # Use Rails config if available
      rails_config = Rails.application.config.grape_rails_logger
      config_obj = Config.new
      config_obj.enabled = rails_config.enabled if rails_config.respond_to?(:enabled)
      config_obj.subscriber_class = rails_config.subscriber_class if rails_config.respond_to?(:subscriber_class)
      config_obj.logger = rails_config.logger if rails_config.respond_to?(:logger)
      config_obj.tag = rails_config.tag if rails_config.respond_to?(:tag)
      config_obj
    else
      # Fall back to module-level config for non-Rails usage
      config
    end
  end
end

# Only load Railtie if Rails::Railtie is available (real Rails app, not test stub)
require_relative "grape_rails_logger/railtie" if defined?(Rails) && defined?(Rails::Railtie)
