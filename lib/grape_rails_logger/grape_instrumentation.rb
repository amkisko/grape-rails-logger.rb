module GrapeRailsLogger
  # Thread-safe storage for DB timing metrics per request
  module Timings
    # Use IsolatedExecutionState for Rails 7.1+ thread/Fiber safety
    # Falls back to Thread.current for Rails 6-7.0
    if defined?(ActiveSupport::IsolatedExecutionState)
      def self.execution_state
        ActiveSupport::IsolatedExecutionState
      end
    else
      def self.execution_state
        Thread.current
      end
    end

    def self.reset_db_runtime
      state = execution_state
      state[:grape_db_runtime] = 0
      state[:grape_db_calls] = 0
    end

    def self.db_runtime
      execution_state[:grape_db_runtime] ||= 0
    end

    def self.db_calls
      execution_state[:grape_db_calls] ||= 0
    end

    def self.append_db_runtime(event)
      state = execution_state
      state[:grape_db_runtime] = (state[:grape_db_runtime] || 0) + event.duration
      state[:grape_db_calls] = (state[:grape_db_calls] || 0) + 1
    end
  end

  # Middleware that instruments Grape API requests with timing and logging
  #
  # This middleware uses ActiveSupport::Notifications to emit events without
  # interfering with the request flow. All logging happens asynchronously via
  # subscribers, ensuring that logging failures never break requests.
  #
  # @example Basic usage
  #   class API < Grape::API
  #     use GrapeRailsLogger::GrapeInstrumentation
  #   end
  #
  # @example With options (future extensibility)
  #   class API < Grape::API
  #     use GrapeRailsLogger::GrapeInstrumentation, enabled: true
  #   end
  class GrapeInstrumentation < ::Grape::Middleware::Base
    DEFAULT_OPTIONS = {
      enabled: true
    }.freeze

    attr_accessor :response_status, :response_body

    # Override call! to wrap with ActiveSupport::Notifications
    # This ensures the entire request lifecycle is instrumented
    def call!(env)
      # Check if enabled (default to true if not explicitly set)
      enabled = options.fetch(:enabled, DEFAULT_OPTIONS[:enabled])
      return @app.call(env) unless enabled

      @env = env
      @app_response = nil
      # Get logger from options, config, or default to Rails.logger
      logger = options[:logger] || effective_logger

      # Grape's error handling flow:
      # 1. Error middleware's call! uses: error_response(catch(:error) { return @app.call(@env) })
      # 2. If @app.call(@env) raises, rescue Exception catches it
      # 3. Calls run_rescue_handler(find_handler(e.class), e, endpoint)
      # 4. run_rescue_handler calls rescue_from handler (wrapped in catch(:error))
      # 5. rescue_from handler calls error! which throws :error
      # 6. The :error is caught, error_response creates a Rack response, and it's returned
      #
      # The PROBLEM: Error middleware is in @app, so when we call @app.call(@env),
      # Error middleware should catch exceptions and process them. But the notification
      # block might complete before Error middleware's rescue_from handler runs.
      #
      # The SOLUTION: We need to ensure that @app.call(@env) completes (and Error middleware
      # processes any exceptions) BEFORE we collect data and the notification block completes.
      # The key is that @app.call(@env) should block until Error middleware returns a response.
      #
      # We wrap the entire request in the notification block so duration is tracked
      # and the subscriber is called. Data collection happens AFTER @app.call completes,
      # ensuring we capture the final response status from Error middleware.
      ActiveSupport::Notifications.instrument("grape.request", env: env, logger: logger) do |payload|
        before_call

        # Call the app - Error middleware will catch exceptions and call rescue_from handlers
        # This call should BLOCK until Error middleware has fully processed any exceptions
        # and returned a response (even if it's an error response).
        # Error middleware's error_response sets env[Grape::Env::API_ENDPOINT].status(status)
        # before returning the Rack response, so the endpoint status is set correctly.
        begin
          @app_response = @app.call(@env)
        rescue => e
          # If an exception propagates out of @app.call, it means Error middleware didn't catch it
          # This shouldn't happen, but we need to handle it defensively
          # Store the exception for logging, but don't set @app_response
          payload[:exception_object] = e
          @app_response = nil
          # Extract status from exception before re-raising so subscriber has it
          status = StatusExtractor.extract_status_from_exception(e)
          payload[:status] = status if status.is_a?(Integer)
          # Re-raise to let Rails handle it (or Error middleware at a higher level)
          raise e
        end

        # NOW collect all data AFTER Error middleware has processed the exception
        # At this point, @app_response should contain the final Rack response with correct status
        # and env[Grape::Env::API_ENDPOINT].status should be set to the correct value

        # Check if there was an exception that Grape handled (for logging purposes)
        # This is in addition to any exception we caught above
        if @env.is_a?(Hash) && @env[Grape::Env::API_ENDPOINT]
          endpoint = @env[Grape::Env::API_ENDPOINT]
          # Check various places where Grape might store exception info
          if endpoint.respond_to?(:options) && endpoint.options.is_a?(Hash)
            exception = endpoint.options[:exception] || endpoint.options["exception"] ||
              endpoint.options[:error] || endpoint.options["error"]
            payload[:exception_object] = exception if exception.is_a?(Exception)
          end
          # Also check if endpoint has exception methods
          if endpoint.respond_to?(:exception) && endpoint.exception.is_a?(Exception) && !payload[:exception_object]
            payload[:exception_object] = endpoint.exception
          end
        end

        # Capture response metadata - @app_response contains the final response
        # from Error middleware with the correct status code (set by error_response)
        safely_capture_response_metadata(payload)
        payload[:db_runtime] = Timings.db_runtime
        payload[:db_calls] = Timings.db_calls

        # Return the response - subscriber will log it using the collected data
        # This return value is what ActiveSupport::Notifications uses to complete the block
        @app_response
      end
    rescue => e
      # If ActiveSupport::Notifications fails, still process the request
      # This should never happen, but we're defensive
      handle_instrumentation_error(e)
      raise e
    end

    private

    def effective_logger
      # First check Rails config if available
      if defined?(Rails) && Rails.application && Rails.application.config.respond_to?(:grape_rails_logger)
        config_logger = Rails.application.config.grape_rails_logger.logger
        return config_logger if config_logger
      end

      # Fall back to Rails.logger if available
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        return Rails.logger
      end

      nil
    end

    def before_call
      Timings.reset_db_runtime
    rescue => e
      # Never fail the request if timing reset fails
      log_instrumentation_error("Failed to reset DB runtime", e)
    end

    def safely_capture_response_metadata(payload)
      capture_response_metadata(payload)
    rescue => e
      # Never fail the request if metadata capture fails
      log_instrumentation_error("Failed to capture response metadata", e)
    end

    def capture_response_metadata(payload)
      # Understanding Grape's error handling flow:
      # 1. Exception is raised in endpoint
      # 2. Error middleware's `rescue Exception` catches it
      # 3. Calls `run_rescue_handler(find_handler(e.class), e, endpoint)`
      # 4. `run_rescue_handler` calls `rescue_from` handler wrapped in `catch(:error)`
      # 5. `rescue_from` calls `error!({error: ...}, 400)` which throws `:error` with `{status: 400, ...}`
      # 6. `catch(:error)` catches it, returns error hash `{status: 400, ...}`
      # 7. `error_response({status: 400, ...})` is called
      # 8. `error_response` sets `env[Grape::Env::API_ENDPOINT].status(400)` (line 55)
      # 9. `error_response` returns `rack_response(400, headers, body)` = `[400, headers, body]`
      # 10. `run_rescue_handler` returns the Rack response
      # 11. Error middleware's `call!` returns the Rack response
      # 12. `@app.call(@env)` returns the Rack response
      #
      # At this point, both endpoint.status and @app_response[0] should be 400
      # We prioritize endpoint.status because it's set explicitly by Error middleware,
      # but the Rack response status should match.
      #
      # Priority order:
      # 1. @app_response[0] (Rack response status) - this is what Error middleware actually returned
      # 2. endpoint.status (set by Error middleware's error_response) - should match response
      # 3. Fallback to extract_status in subscriber

      if @app_response
        # PRIORITY 1: Extract status from Rack response array - this is what Error middleware returned
        # This is the ACTUAL response that rescue_from's error! call created
        status = extract_status_from_response(@app_response)
        _, _, resp = *@app_response

        after_call(status, resp)

        # Use response status - this is what Error middleware returned after rescue_from ran
        if status.is_a?(Integer)
          payload[:status] = status
        end
        payload[:response] = @app_response
      end

      # PRIORITY 2: Check endpoint.status as a fallback/verification
      # This should match the response status, but we use it as a fallback if response is missing
      endpoint = @env.is_a?(Hash) ? @env[Grape::Env::API_ENDPOINT] : nil
      if endpoint&.respond_to?(:status) && !payload[:status]
        endpoint_status = begin
          endpoint.status
        rescue
          # If status method raises, ignore it
          nil
        end

        if endpoint_status.is_a?(Integer)
          payload[:status] = endpoint_status
        end
      end

      # If we still don't have a status but have an exception, extract status from exception
      if payload[:exception_object] && !payload[:status]
        status = StatusExtractor.extract_status_from_exception(payload[:exception_object])
        payload[:status] = status if status.is_a?(Integer)
      end
    end

    def extract_status_from_response(response)
      return nil unless response

      # Error middleware's rack_response returns Rack::Response, which Base.call converts to array via to_a
      # But check both formats to be safe
      if response.is_a?(Array) && response[0].is_a?(Integer)
        # Rack response format: [status, headers, body]
        response[0]
      elsif response.respond_to?(:to_a)
        # Rack::Response object - convert to array first
        array = response.to_a
        array[0] if array.is_a?(Array) && array[0].is_a?(Integer)
      elsif response.respond_to?(:status) && response.status.is_a?(Integer)
        response.status
      else
        nil
      end
    end

    def after_call(status, response)
      @response_status = status
      @response_body = response
    end

    def handle_instrumentation_error(error)
      # Last resort: if instrumentation itself fails, silently handle the error
      # The request will still be processed, we just won't have logging
    end

    def log_instrumentation_error(message, error)
      # Don't log here - logging happens only in subscriber
      # This is just for error tracking - actual logging happens in subscriber
    end
  end

  # Shared utility for extracting HTTP status codes from exceptions
  module StatusExtractor
    module_function

    # Common exception to status code mappings
    EXCEPTION_STATUS_MAP = {
      "ActiveRecord::RecordNotFound" => 404,
      "ActiveRecord::RecordNotUnique" => 409,
      "ActiveRecord::RecordInvalid" => 422,
      "ActiveRecord::StatementInvalid" => 422,
      "ActionController::RoutingError" => 404,
      "ActionController::MethodNotAllowed" => 405,
      "ActionController::NotImplemented" => 501,
      "ActionController::UnknownFormat" => 406,
      "ActionController::BadRequest" => 400,
      "ActionController::ParameterMissing" => 400
    }.freeze

    # Extracts HTTP status code from an exception
    #
    # @param e [Exception] The exception to extract status from
    # @return [Integer] HTTP status code, defaults to 500
    def extract_status_from_exception(e)
      return e.status if e.respond_to?(:status) && e.status.is_a?(Integer)

      if e.instance_variable_defined?(:@status)
        status = e.instance_variable_get(:@status)
        return status if status.is_a?(Integer)
      end

      if e.respond_to?(:options) && e.options.is_a?(Hash)
        return e.options[:status] if e.options[:status].is_a?(Integer)
      end

      # Check common exception type mappings
      exception_class_name = e.class.name
      return EXCEPTION_STATUS_MAP[exception_class_name] if EXCEPTION_STATUS_MAP.key?(exception_class_name)

      # Check if any ancestor class matches
      EXCEPTION_STATUS_MAP.each do |exception_name, status_code|
        # Use safe_constantize if available (ActiveSupport), otherwise constantize
        exception_class = if exception_name.respond_to?(:safe_constantize)
          exception_name.safe_constantize
        else
          exception_name.constantize
        end
        return status_code if exception_class && e.is_a?(exception_class)
      rescue NameError
        # Exception class not available, skip
      end

      500
    end
  end

  # Subscriber that logs Grape API requests with structured data
  #
  # Automatically subscribed to "grape.request" notifications.
  # Logs structured hash data compatible with JSON loggers.
  #
  # This class is designed to be exception-safe: any error in logging
  # is caught and logged separately, never breaking the request flow.
  class GrapeRequestLogSubscriber
    # Custom error class to distinguish logging errors from other errors
    class LoggingError < StandardError
      attr_reader :original_error

      def initialize(original_error)
        @original_error = original_error
        super("Logging failed: #{original_error.class}: #{original_error.message}")
      end
    end

    FILTERED_PARAMS = %w[password secret token key].freeze
    PARAM_EXCEPTIONS = %w[controller action format].freeze
    AD_PARAMS = "action_dispatch.request.parameters"

    def grape_request(event)
      return unless event.is_a?(ActiveSupport::Notifications::Event)

      env = event.payload[:env]
      return unless env.is_a?(Hash)

      # Get logger from event payload (passed from middleware)
      logger = event.payload[:logger]

      logged_successfully = false
      begin
        endpoint = env[Grape::Env::API_ENDPOINT] if env.is_a?(Hash)
        request = (endpoint&.respond_to?(:request) && endpoint.request) ? endpoint.request : nil

        data = build_log_data(event, request, env)
        logged_successfully = log_data(data, event.payload[:exception_object], logger)
        event.payload[:logged_successfully] = true if logged_successfully
      rescue LoggingError
        # If logging itself failed, don't try to log again (would cause infinite loop or duplicates)
        # The error was already logged in safe_log's rescue block
        # Silently skip to avoid duplicate logs
      rescue => e
        # Only call fallback if we haven't successfully logged yet
        # This prevents duplicate logs when logging succeeds but something else fails
        unless logged_successfully
          log_fallback_subscriber_error(event, e, logger)
        end
      end
    end

    private

    def build_request(env)
      ::Grape::Request.new(env)
    rescue
      nil
    end

    def build_log_data(event, request, env)
      db_runtime = event.payload[:db_runtime] || 0
      db_calls = event.payload[:db_calls] || 0
      total_runtime = begin
        event.duration || 0
      rescue
        0
      end

      status = extract_status(event) || (event.payload[:exception_object] ? 500 : 200)
      rails_request = rails_request_for(env)
      method = request ? safe_string(request.request_method) : safe_string(env["REQUEST_METHOD"])
      path = request ? safe_string(request.path) : safe_string(env["PATH_INFO"] || env["REQUEST_URI"])

      {
        method: method,
        path: path,
        format: extract_format(request, env),
        controller: extract_controller(event),
        source_location: extract_source_location(event),
        action: extract_action(event) || "unknown",
        status: status,
        host: extract_host(rails_request, request),
        remote_addr: extract_remote_addr(rails_request, request),
        request_id: extract_request_id(rails_request, env),
        duration: total_runtime.round(2),
        db: db_runtime.round(2),
        db_calls: db_calls,
        params: filter_params(extract_params(request, env))
      }
    end

    def rails_request_for(env)
      return nil unless defined?(ActionDispatch::Request)

      ActionDispatch::Request.new(env)
    rescue
      nil
    end

    def extract_host(rails_request, grape_request)
      # Prefer Rails ActionDispatch::Request#host if available
      if rails_request&.respond_to?(:host)
        safe_string(rails_request.host)
      else
        safe_string(grape_request.host)
      end
    end

    def extract_remote_addr(rails_request, grape_request)
      # Prefer Rails ActionDispatch::Request#remote_ip if available
      if rails_request&.respond_to?(:remote_ip)
        safe_string(rails_request.remote_ip)
      elsif rails_request&.respond_to?(:ip)
        safe_string(rails_request.ip)
      elsif grape_request&.respond_to?(:ip)
        safe_string(grape_request.ip)
      end
    end

    def extract_request_id(rails_request, env)
      # Prefer Rails ActionDispatch::Request#request_id if available
      if rails_request&.respond_to?(:request_id)
        safe_string(rails_request.request_id)
      else
        safe_string(env["action_dispatch.request_id"])
      end
    end

    def log_data(data, exception_object, logger = nil)
      if exception_object
        data[:exception] = build_exception_data(exception_object)
        safe_log(:error, data, logger)
      else
        safe_log(:info, data, logger)
      end
      # Mark that we successfully logged to prevent fallback from duplicating
      true
    rescue => e
      # If logging itself fails, don't log again in fallback
      # Mark that we tried to log so fallback knows not to duplicate
      raise LoggingError.new(e)
    end

    def build_exception_data(exception)
      data = {
        class: exception.class.name,
        message: exception.message
      }
      # Use Rails.env for environment checks (Rails-native)
      if defined?(Rails) && Rails.respond_to?(:env) && !Rails.env.production?
        data[:backtrace] = exception.backtrace&.first(10)
      end
      data
    rescue => e
      {class: "Unknown", message: "Failed to extract exception data: #{e.message}"}
    end

    def safe_log(level, data, logger = nil)
      # Get logger from parameter, config, or default to Rails.logger
      effective_logger = logger || resolve_effective_logger
      return unless effective_logger

      # Get tag from config
      tag = resolve_tag

      if effective_logger.respond_to?(:tagged) && tag
        effective_logger.tagged(tag) do
          effective_logger.public_send(level, data)
        end
      else
        effective_logger.public_send(level, data)
      end
    rescue => e
      # Fallback to stderr if logging fails - never raise
      # Only warn in development to avoid noise in production
      if defined?(Rails) && Rails.respond_to?(:env) && Rails.env.development?
        Rails.logger&.warn("GrapeRailsLogger log error: #{e.message}")
      end
    end

    def resolve_tag
      # First check Rails config if available
      if defined?(Rails) && Rails.application && Rails.application.config.respond_to?(:grape_rails_logger)
        config_tag = Rails.application.config.grape_rails_logger.tag
        return config_tag if config_tag
      end

      # Fall back to module config
      if defined?(GrapeRailsLogger) && GrapeRailsLogger.respond_to?(:effective_config)
        config = GrapeRailsLogger.effective_config
        return config.tag if config.respond_to?(:tag) && config.tag
      end

      # Default tag
      "Grape"
    end

    def resolve_effective_logger
      # First check Rails config if available
      if defined?(Rails) && Rails.application && Rails.application.config.respond_to?(:grape_rails_logger)
        config_logger = Rails.application.config.grape_rails_logger.logger
        return config_logger if config_logger
      end

      # Fall back to Rails.logger if available
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        return Rails.logger
      end

      nil
    end

    def log_fallback_subscriber_error(event, error, logger = nil)
      # Try to build a proper HTTP request log even when subscriber processing fails
      # This should only be called if there's an error in the subscriber itself,
      # not if there's a request exception (which is already logged by log_data)
      env = event.payload[:env]
      return unless env.is_a?(Hash)

      # If the error is the same as the exception_object, it means we already logged it
      # in the normal path, so skip duplicate logging
      return if error == event.payload[:exception_object]

      # If the error is a LoggingError, it means logging already failed and was handled
      # Don't try to log again as it would cause duplicates
      return if error.is_a?(LoggingError)

      # If we successfully logged in the normal path, don't log again
      # This prevents duplicates when logging succeeds but something else fails
      return if event.payload[:logged_successfully] == true

      # Double-check: if we can see the logged_successfully flag was set, definitely skip
      # This is a safety check in case the flag was set but we're still being called
      return if event.payload.key?(:logged_successfully) && event.payload[:logged_successfully]

      # Get logger from parameter or event payload
      # Make sure we use the tagged logger if available, not raw Rails.logger
      effective_logger = logger || event.payload[:logger] || resolve_effective_logger

      begin
        # Extract status using the same priority as extract_status
        # This ensures consistency - always use response status, not exception status
        status = extract_status(event)

        total_runtime = begin
          event.duration || 0
        rescue
          0
        end

        # Try to build request, but don't fail if it doesn't work
        request = begin
          build_request(env)
        rescue
          # If build_request fails, we'll extract from env directly
          nil
        end

        # Build minimal log data - extract what we can even if request building fails
        rails_request = begin
          rails_request_for(env)
        rescue
          nil
        end

        # Safely extract all fields with fallbacks
        method = begin
          request ? safe_string(request.request_method) : safe_string(env["REQUEST_METHOD"])
        rescue
          safe_string(env["REQUEST_METHOD"])
        end

        path = begin
          request ? safe_string(request.path) : safe_string(env["PATH_INFO"] || env["REQUEST_URI"])
        rescue
          safe_string(env["PATH_INFO"] || env["REQUEST_URI"])
        end

        format_val = begin
          request ? extract_format(request, env) : extract_format_from_env(env)
        rescue
          extract_format_from_env(env)
        end

        host = begin
          request ? extract_host(rails_request, request) : extract_host_from_env(rails_request, env)
        rescue
          extract_host_from_env(rails_request, env)
        end

        remote_addr = begin
          request ? extract_remote_addr(rails_request, request) : extract_remote_addr_from_env(rails_request, env)
        rescue
          extract_remote_addr_from_env(rails_request, env)
        end

        request_id = begin
          extract_request_id(rails_request, env)
        rescue
          safe_string(env["action_dispatch.request_id"])
        end

        # Extract db_runtime and db_calls from event payload if available
        db_runtime = begin
          (event.payload[:db_runtime] || 0).round(2)
        rescue
          0
        end
        db_calls = begin
          event.payload[:db_calls] || 0
        rescue
          0
        end

        # Try to extract action and controller even in fallback mode
        action = begin
          extract_action(event) || "unknown"
        rescue
          "unknown"
        end
        controller = begin
          extract_controller(event)
        rescue
          nil
        end

        data = {
          method: method,
          path: path,
          format: format_val,
          status: status,
          host: host,
          remote_addr: remote_addr,
          request_id: request_id,
          duration: total_runtime.round(2),
          db: db_runtime,
          db_calls: db_calls,
          action: action,
          controller: controller,
          exception: {
            class: error.class.name,
            message: error.message
          }
        }

        # Use the original exception if available, otherwise use the subscriber error
        # Only include exception details if this is a subscriber error, not a request exception
        # (request exceptions are already logged by the normal path)
        if (original_exception = event.payload[:exception_object])
          # If there's an original exception AND the error is the same, we already logged it
          # Skip logging to avoid duplicates
          if error == original_exception
            return
          end
          # If they're different, include the original exception details
          data[:exception][:class] = original_exception.class.name
          data[:exception][:message] = original_exception.message
          if defined?(Rails) && Rails.respond_to?(:env) && !Rails.env.production?
            data[:exception][:backtrace] = original_exception.backtrace&.first(10)
          end
        elsif defined?(Rails) && Rails.respond_to?(:env) && !Rails.env.production?
          data[:exception][:backtrace] = error.backtrace&.first(10)
        end

        safe_log(:error, data, effective_logger)
      rescue
        # If even fallback logging fails, don't try to log again
        # Silently fail to avoid infinite loops or noise
      end
    end

    def extract_format_from_env(env)
      # First check Grape's api.format
      env_fmt = env["api.format"]
      if env_fmt
        fmt = env_fmt.to_s.sub(/^\./, "").downcase
        return fmt unless fmt.empty?
      end

      # Try to determine format from Content-Type using Grape's content type mappings
      format_from_content_type = extract_format_from_content_type(env)
      return format_from_content_type if format_from_content_type

      # Fall back to rack.request.formats
      rack_fmt = env["rack.request.formats"]&.first
      if rack_fmt
        fmt = rack_fmt.to_s.sub(/^\./, "").downcase
        return fmt unless fmt.empty?
      end

      # Fall back to content type string parsing
      content_type = env["CONTENT_TYPE"] || env["HTTP_CONTENT_TYPE"]
      if content_type
        fmt = content_type.to_s.sub(/^\./, "").downcase
        return fmt unless fmt.empty?
      end

      "json"
    end

    def extract_host_from_env(rails_request, env)
      if rails_request&.respond_to?(:host)
        safe_string(rails_request.host)
      else
        safe_string(env["HTTP_HOST"] || env["SERVER_NAME"])
      end
    end

    def extract_remote_addr_from_env(rails_request, env)
      if rails_request&.respond_to?(:remote_ip)
        safe_string(rails_request.remote_ip)
      elsif rails_request&.respond_to?(:ip)
        safe_string(rails_request.ip)
      else
        x_forwarded_for = env["HTTP_X_FORWARDED_FOR"]
        if x_forwarded_for
          first_ip = x_forwarded_for.split(",").first&.strip
          return safe_string(first_ip) if first_ip
        end
        safe_string(env["REMOTE_ADDR"])
      end
    end

    def safe_string(value)
      return nil if value.nil?
      value.to_s
    rescue
      nil
    end

    def extract_status(event)
      # PRIORITY 1: Status already captured from response (most reliable)
      # This is set in capture_response_metadata AFTER Grape's rescue_from handlers
      # This is the SINGLE SOURCE OF TRUTH - the response from Error middleware
      status = event.payload[:status]
      return status if status.is_a?(Integer)

      # PRIORITY 2: Extract from response array directly
      # This is the actual Rack response that Error middleware returned
      response = event.payload[:response]
      if response.is_a?(Array) && response[0].is_a?(Integer)
        return response[0]
      end

      # PRIORITY 3: Get from endpoint status (set by Error middleware's error_response)
      # Error middleware sets env[Grape::Env::API_ENDPOINT].status(status) when processing errors
      # This should have been captured in capture_response_metadata, but we check again here
      # as a fallback in case capture_response_metadata didn't run or failed
      env = event.payload[:env]
      if env.is_a?(Hash) && env[Grape::Env::API_ENDPOINT]
        endpoint = env[Grape::Env::API_ENDPOINT]
        if endpoint.respond_to?(:status)
          endpoint_status = begin
            endpoint.status
          rescue
            # If status method raises, ignore it
            nil
          end

          if endpoint_status.is_a?(Integer) && endpoint_status >= 400
            # Only use endpoint status if it's an error status (4xx or 5xx)
            # This ensures we're not using stale status from a previous request
            return endpoint_status
          end
        end
      end

      # PRIORITY 4: Fall back to exception-based status (only if no response available)
      # This should rarely happen - Grape's rescue_from should return a response
      if (exception = event.payload[:exception_object])
        status = StatusExtractor.extract_status_from_exception(exception)
        return status if status.is_a?(Integer)
      end

      # Default fallback - if we have an exception, assume 500
      # If no exception, assume 200 (success)
      event.payload[:exception_object] ? 500 : 200
    end

    def extract_action(event)
      endpoint = event.payload.dig(:env, "api.endpoint")
      return "unknown" unless endpoint
      return "unknown" unless endpoint.respond_to?(:options)
      return "unknown" unless endpoint.options

      method = endpoint.options[:method]&.first
      path = endpoint.options[:path]&.first
      return "unknown" unless method && path

      return method.downcase.to_s if path == "/" || path.empty?

      clean_path = path.to_s.delete_prefix("/").gsub(/[:\/]/, "_").squeeze("_").gsub(/^_+|_+$/, "")
      "#{method.downcase}_#{clean_path}"
    rescue
      "unknown"
    end

    def extract_controller(event)
      endpoint = event.payload.dig(:env, "api.endpoint")
      return nil unless endpoint&.source&.source_location

      file_path = endpoint.source.source_location.first
      return nil unless file_path

      rails_root = safe_rails_root
      return nil unless rails_root

      prefix = File.join(rails_root, "app/api/")
      path_without_prefix = file_path.delete_prefix(prefix).sub(/\.rb\z/, "")

      # Use ActiveSupport::Inflector.camelize (Rails-native) which converts
      # file paths to class names (e.g., "users" -> "Users", "users/profile" -> "Users::Profile")
      # This matches Rails generator conventions for converting file paths to class names
      if defined?(ActiveSupport::Inflector)
        ActiveSupport::Inflector.camelize(path_without_prefix)
      else
        # Fallback for non-Rails: split by /, capitalize each part, join with ::
        path_without_prefix.split("/").map(&:capitalize).join("::")
      end
    rescue
      nil
    end

    def extract_source_location(event)
      endpoint = event.payload.dig(:env, "api.endpoint")
      return nil unless endpoint&.source&.source_location

      loc = endpoint.source.source_location.first
      line = endpoint.source.source_location.last
      return nil unless loc

      rails_root = safe_rails_root
      if rails_root && loc.start_with?(rails_root)
        loc = loc.delete_prefix(rails_root + "/")
      end

      "#{loc}:#{line}"
    rescue
      nil
    end

    def safe_rails_root
      return nil unless defined?(Rails)
      return nil unless Rails.respond_to?(:root)

      root = Rails.root
      return nil if root.nil?

      # Use Rails.root.to_s which handles Pathname correctly
      root.to_s
    rescue
      nil
    end

    def extract_params(request, env = nil)
      return {} unless env.is_a?(Hash)

      endpoint = env[Grape::Env::API_ENDPOINT]
      return {} unless endpoint&.respond_to?(:request) && endpoint.request

      endpoint_params = endpoint.request.params
      return {} if endpoint_params.nil? || endpoint_params.empty?

      params_hash = if endpoint_params.respond_to?(:to_unsafe_h)
        endpoint_params.to_unsafe_h
      elsif endpoint_params.respond_to?(:to_h)
        endpoint_params.to_h
      else
        endpoint_params.is_a?(Hash) ? endpoint_params : {}
      end
      return params_hash.except("route_info", :route_info) unless params_hash.empty?

      # Fallback: Parse JSON body for non-standard JSON content types
      req = endpoint.request
      content_type = req.content_type || req.env["CONTENT_TYPE"] || ""
      return {} if !((content_type.include?("json") || content_type.include?("application/vnd.api")) && req.env["rack.input"])

      begin
        original_pos = begin
          req.env["rack.input"].pos
        rescue
          0
        end
        begin
          req.env["rack.input"].rewind
        rescue
          nil
        end
        body_content = begin
          req.env["rack.input"].read
        rescue
          nil
        end
        req.env["rack.input"].pos = begin
          original_pos
        rescue
          nil
        end

        if body_content && !body_content.empty?
          parsed_json = begin
            JSON.parse(body_content)
          rescue
            nil
          end
          return parsed_json.except("route_info", :route_info) if parsed_json.is_a?(Hash)
        end
      rescue
      end

      {}
    rescue
      {}
    end

    def extract_format(request, env = nil)
      env ||= request.env if request.respond_to?(:env)

      # First check Grape's api.format (most reliable for Grape APIs)
      # This is set by Grape based on Content-Type and Accept headers
      if env.is_a?(Hash)
        env_fmt = env["api.format"]
        if env_fmt
          # Remove leading dot if present and convert to string
          fmt = env_fmt.to_s.sub(/^\./, "").downcase
          return fmt unless fmt.empty?
        end
      end

      # Try Grape's request.format method
      fmt = request.try(:format)
      if fmt
        fmt_str = fmt.to_s.sub(/^\./, "").downcase
        return fmt_str unless fmt_str.empty?
      end

      # Try to determine format from Content-Type using Grape's content type mappings
      # This is generic and works with any custom content types defined in the API
      if env.is_a?(Hash)
        format_from_content_type = extract_format_from_content_type(env)
        return format_from_content_type if format_from_content_type
      end

      # Fall back to Rails ActionDispatch::Request#format
      if defined?(ActionDispatch::Request) && env.is_a?(Hash)
        begin
          rails_request = ActionDispatch::Request.new(env)
          if rails_request.respond_to?(:format) && rails_request.format
            fmt_str = rails_request.format.to_sym.to_s.downcase
            return fmt_str unless fmt_str.empty?
          end
        rescue
          # Fall through to other detection methods
        end
      end

      # Fall back to rack.request.formats
      if env.is_a?(Hash)
        rack_fmt = env["rack.request.formats"]&.first
        if rack_fmt
          fmt_str = rack_fmt.to_s.sub(/^\./, "").downcase
          return fmt_str unless fmt_str.empty?
        end
      end

      # Default to json if nothing found
      "json"
    end

    def extract_format_from_content_type(env)
      return nil unless env.is_a?(Hash)

      content_type = env["CONTENT_TYPE"] || env["HTTP_CONTENT_TYPE"]
      accept = env["HTTP_ACCEPT"]
      return nil unless content_type || accept

      endpoint = env["api.endpoint"]
      return nil unless endpoint

      api_class = endpoint.respond_to?(:options) ? endpoint.options[:for] : nil
      api_class ||= endpoint.respond_to?(:namespace) ? endpoint.namespace&.options&.dig(:for) : nil
      api_class ||= endpoint.respond_to?(:route) ? endpoint.route&.options&.dig(:for) : nil
      return nil unless api_class&.respond_to?(:content_types, true)

      begin
        content_types = api_class.content_types
        return nil unless content_types.is_a?(Hash)

        content_types.each do |format_name, mime_type|
          mime_types = mime_type.is_a?(Array) ? mime_type : [mime_type]
          if content_type && mime_types.any? { |mime| content_type.include?(mime.to_s) }
            return format_name.to_s.downcase
          end
          if accept && mime_types.any? { |mime| accept.include?(mime.to_s) }
            return format_name.to_s.downcase
          end
        end
      rescue
      end

      nil
    end

    def filter_params(params)
      return {} unless params
      return {} unless params.is_a?(Hash)

      cleaned = if (filter = rails_parameter_filter)
        # Create a deep copy since filter modifies in place (Rails 6+)
        params_copy = params.respond_to?(:deep_dup) ? params.deep_dup : params.dup
        filter.filter(params_copy)
      else
        filter_parameters_manually(params)
      end

      cleaned.is_a?(Hash) ? cleaned.reject { |key, _| PARAM_EXCEPTIONS.include?(key.to_s) } : {}
    rescue
      # Don't log - just fallback to manual filtering
      # Logging happens only in subscriber
      filter_parameters_manually(params).reject { |key, _| PARAM_EXCEPTIONS.include?(key.to_s) }
    end

    def rails_parameter_filter
      # Use Rails.application.config.filter_parameters (Rails-native configuration)
      return nil unless defined?(Rails) && defined?(Rails.application)
      return nil unless Rails.application.config.respond_to?(:filter_parameters)

      filter_parameters = Rails.application.config.filter_parameters
      return nil if filter_parameters.nil? || filter_parameters.empty?

      # Prefer ActiveSupport::ParameterFilter (Rails 6.1+)
      # This is the Rails-native parameter filtering system
      if defined?(ActiveSupport::ParameterFilter)
        ActiveSupport::ParameterFilter.new(filter_parameters)
      # Fall back to ActionDispatch::Http::ParameterFilter (Rails 6.0 and earlier)
      elsif defined?(ActionDispatch::Http::ParameterFilter)
        ActionDispatch::Http::ParameterFilter.new(filter_parameters)
      end
    rescue
      # Log but don't fail - fall back to manual filtering
      # Don't log - just return nil
      # Logging happens only in subscriber
      nil
    end

    def filter_parameters_manually(params, depth = 0)
      return {} unless params
      return {"[FILTERED]" => "[max_depth_exceeded]"} if depth > 10

      return {} unless params.is_a?(Hash)

      params.each_with_object({}) do |(key, value), result|
        next if result.size >= 50 # Limit hash size

        result[key] = if should_filter_key?(key)
          # When key should be filtered, replace the value (not the key name)
          "[FILTERED]"
        else
          case value
          when Hash
            filter_parameters_manually(value, depth + 1)
          when Array
            value.first(100).map { |v| v.is_a?(Hash) ? filter_parameters_manually(v, depth + 1) : filter_value(v) }
          else
            filter_value(value)
          end
        end
      end
    rescue
      # Don't log - just return empty hash
      # Logging happens only in subscriber
      {}
    end

    def filter_value(value)
      return value unless value.is_a?(String)
      value_lower = value.downcase
      return "[FILTERED]" if FILTERED_PARAMS.any? { |param| value_lower.include?(param.downcase) }

      value
    end

    def should_filter_key?(key)
      key_lower = key.to_s.downcase
      FILTERED_PARAMS.any? { |param| key_lower.include?(param.downcase) }
    end
  end
end
