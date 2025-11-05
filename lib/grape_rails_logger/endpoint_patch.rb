# frozen_string_literal: true

module GrapeRailsLogger
  # Monkey patch Grape::Endpoint#build_stack to wrap the final Rack app
  # This ensures we capture the response AFTER Error middleware has fully processed it
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
