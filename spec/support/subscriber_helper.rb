# Helper to set up subscribers in test environment
# Since Rails.application isn't fully initialized in tests,
# we need to manually set up the subscribers

module SubscriberHelper
  def setup_endpoint_patch
    # Patch Grape::Endpoint#build_stack to use EndpointWrapper (same as Railtie does)
    # Only patch if not already patched
    unless Grape::Endpoint.ancestors.include?(GrapeRailsLogger::EndpointPatch)
      Grape::Endpoint.prepend(GrapeRailsLogger::EndpointPatch)
    end
  end

  def setup_subscribers
    # Clear any existing subscribers to avoid duplicates
    # Note: We can't easily unsubscribe, so we'll just add new ones
    # In tests, this is fine since we control the environment

    # Subscribe to Grape request events for logging
    ActiveSupport::Notifications.subscribe("grape.request") do |*args|
      next unless Rails.application.config.respond_to?(:grape_rails_logger)
      next unless Rails.application.config.grape_rails_logger.enabled

      begin
        subscriber_class = Rails.application.config.grape_rails_logger.subscriber_class || GrapeRailsLogger::GrapeRequestLogSubscriber
        subscriber = subscriber_class.new
        subscriber.grape_request(ActiveSupport::Notifications::Event.new(*args))
      rescue
        # Never let logging errors break tests
      end
    end

    # Subscribe to ActiveRecord SQL events for DB timing aggregation
    if defined?(ActiveRecord)
      ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        GrapeRailsLogger::Timings.append_db_runtime(ActiveSupport::Notifications::Event.new(*args))
      rescue
        # Never let DB timing errors break tests
      end
    end
  end
end

RSpec.configure do |config|
  config.include SubscriberHelper

  config.before(:each) do
    # Ensure Rails.application.config.grape_rails_logger is set up
    unless Rails.application.config.respond_to?(:grape_rails_logger)
      config_obj = ActiveSupport::OrderedOptions.new
      config_obj.enabled = true
      config_obj.subscriber_class = GrapeRailsLogger::GrapeRequestLogSubscriber
      Rails.application.config.define_singleton_method(:grape_rails_logger) { config_obj }
    end

    Rails.application.config.grape_rails_logger.enabled = true
    Rails.application.config.grape_rails_logger.subscriber_class = GrapeRailsLogger::GrapeRequestLogSubscriber

    # Set up endpoint patch (automatically patches Grape::Endpoint#build_stack)
    setup_endpoint_patch
    # Set up subscribers
    setup_subscribers
  end
end
