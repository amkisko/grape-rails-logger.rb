require "rails/railtie"

module GrapeRailsLogger
  class Railtie < ::Rails::Railtie
    # Add configuration to Rails.application.config
    config.grape_rails_logger = ActiveSupport::OrderedOptions.new
    config.grape_rails_logger.enabled = true
    config.grape_rails_logger.subscriber_class = GrapeRequestLogSubscriber
    config.grape_rails_logger.logger = nil # Default to nil, will use Rails.logger
    config.grape_rails_logger.tag = "Grape" # Default tag for TaggedLogging

    # Monkey patch Grape::Endpoint#build_stack to wrap the final Rack app
    # This ensures we capture the response AFTER Error middleware has fully processed it
    # Define the module outside the block to avoid constant definition warnings
    module ::GrapeRailsLogger
      module EndpointPatch
        def build_stack(*args)
          app = super
          # Wrap the final Rack app to capture responses after Error middleware
          if ::GrapeRailsLogger.effective_config.enabled
            ::GrapeRailsLogger::EndpointWrapper.new(app, self)
          else
            app
          end
        end
      end
    end

    config.after_initialize do
      # Patch Grape::Endpoint#build_stack to wrap the final Rack app
      # Use prepend to avoid method redefinition issues
      Grape::Endpoint.prepend(::GrapeRailsLogger::EndpointPatch)
      # Subscribe to ActiveRecord SQL events for DB timing aggregation
      # Only subscribe if ActiveRecord is loaded (optional dependency)
      if defined?(ActiveRecord)
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
          GrapeRailsLogger::Timings.append_db_runtime(ActiveSupport::Notifications::Event.new(*args))
        rescue => e
          # Never let DB timing errors break anything
          # Only warn in development to avoid noise in production
          if Rails.env.development?
            Rails.logger.warn("GrapeRailsLogger: Failed to append DB runtime - #{e.class}: #{e.message}")
          end
        end
      end

      # Subscribe to Grape request events for logging
      # Only active if Rails.application.config.grape_rails_logger.enabled is true (default: true)
      # This subscription can be disabled by users if they want to handle logging themselves
      # Logging errors are caught and never propagate to avoid breaking requests
      ActiveSupport::Notifications.subscribe("grape.request") do |*args|
        # Check if logging is enabled before processing
        next unless Rails.application.config.grape_rails_logger.enabled

        begin
          subscriber_class = Rails.application.config.grape_rails_logger.subscriber_class || GrapeRequestLogSubscriber
          subscriber = subscriber_class.new
          subscriber.grape_request(ActiveSupport::Notifications::Event.new(*args))
        rescue => e
          # Last resort: if subscriber creation or invocation fails, log
          # This should never happen, but we're ultra-defensive
          # Only warn in development to avoid noise in production
          if Rails.env.development?
            Rails.logger.warn("GrapeRailsLogger: Subscriber failed - #{e.class}: #{e.message}")
            Rails.logger.warn(e.backtrace&.first(3)&.join("\n")) if e.respond_to?(:backtrace)
          end
        end
      end
    end
  end
end
