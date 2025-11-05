module GrapeRailsLogger
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
end
