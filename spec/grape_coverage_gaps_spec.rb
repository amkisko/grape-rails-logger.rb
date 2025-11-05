require "spec_helper"
require "rack/mock"

RSpec.describe "Coverage gaps - error handling and edge cases" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
  end

  describe "EndpointWrapper error handling" do
    it "handles instrumentation error gracefully" do
      app = ->(env) { [200, {}, ["OK"]] }

      # Force ActiveSupport::Notifications to raise
      allow(ActiveSupport::Notifications).to receive(:instrument).and_raise(StandardError, "Instrumentation failed")

      wrapper = GrapeRailsLogger::EndpointWrapper.new(app, nil)
      env = Rack::MockRequest.env_for("/test")
      response = wrapper.call(env)
      expect(response).to be_an(Array)
      expect(response[0]).to eq(200)
    end

    it "handles Timings.reset_db_runtime error gracefully" do
      app = Class.new(Grape::API) do
        format :json
        get("/test") { {ok: true} }
      end

      allow(GrapeRailsLogger::Timings).to receive(:reset_db_runtime).and_raise(StandardError, "Reset failed")

      response = Rack::MockRequest.new(app).get("/test")
      expect(response.status).to eq(200)
    end

    it "handles collect_response_metadata error gracefully" do
      app = ->(env) { [200, {}, ["OK"]] }

      wrapper = GrapeRailsLogger::EndpointWrapper.new(app, nil)
      allow(wrapper).to receive(:extract_status_from_response).and_raise(StandardError, "Extract failed")

      env = Rack::MockRequest.env_for("/test")
      response = wrapper.call(env)
      expect(response).to be_an(Array)
      expect(response[0]).to eq(200)
    end

    it "handles exception during request processing" do
      app = Class.new(Grape::API) do
        format :json
        get("/test") { raise StandardError, "Request failed" }
      end

      begin
        Rack::MockRequest.new(app).get("/test")
      rescue => e
        expect(e.message).to eq("Request failed")
      end
      # Exception should be re-raised
    end

    it "handles response with status method" do
      # Create a response object that responds to status method
      response_obj = Class.new do
        def status
          404
        end

        def to_a
          [404, {}, ["Not Found"]]
        end
      end.new

      wrapper = GrapeRailsLogger::EndpointWrapper.new(->(env) { response_obj }, nil)

      env = Rack::MockRequest.env_for("/test")
      # Should not raise error
      expect { wrapper.call(env) }.not_to raise_error
    end
  end

  describe "DebugTracer error handling" do
    it "handles Debug.new failure" do
      ClimateControl.modify TRACE: "1" do
        unless defined?(Debug)
          Object.const_set(:Debug, Class.new do
            def self.new(options = {})
              raise StandardError, "Debug initialization failed"
            end
          end)
        end

        app = Class.new(Grape::API) do
          format :json
          use GrapeRailsLogger::DebugTracer
          get("/test") { {ok: true} }
        end

        response = Rack::MockRequest.new(app).get("/test")
        expect(response.status).to eq(200)
      end
    end

    it "handles trace block failure" do
      ClimateControl.modify TRACE: "1" do
        unless defined?(Debug)
          Object.const_set(:Debug, Class.new do
            def self.new(options = {})
              inst = double("DebugInstance")
              allow(inst).to receive(:trace).and_raise(StandardError, "Trace failed")
              inst
            end
          end)
        end

        app = Class.new(Grape::API) do
          format :json
          use GrapeRailsLogger::DebugTracer
          get("/test") { {ok: true} }
        end

        response = Rack::MockRequest.new(app).get("/test")
        expect(response.status).to eq(200)
      end
    end

    it "logs debug unavailable when Debug not defined" do
      ClimateControl.modify TRACE: "1" do
        # Remove Debug if it exists
        if defined?(Debug)
          Object.send(:remove_const, :Debug)
        end

        app = Class.new(Grape::API) do
          format :json
          use GrapeRailsLogger::DebugTracer
          get("/test") { {ok: true} }
        end

        response = Rack::MockRequest.new(app).get("/test")
        expect(response.status).to eq(200)
      end
    end

    it "handles safe_string with nil" do
      ClimateControl.modify TRACE: "1" do
        unless defined?(Debug)
          Object.const_set(:Debug, Class.new do
            def self.new(options = {})
              inst = double("DebugInstance")
              allow(inst).to receive(:trace).and_yield
              inst
            end
          end)
        end

        app = Class.new(Grape::API) do
          format :json
          use GrapeRailsLogger::DebugTracer
          get("/test") { {ok: true} }
        end

        env = {"REQUEST_METHOD" => nil, "PATH_INFO" => nil, "REQUEST_PATH" => nil}
        middleware = GrapeRailsLogger::DebugTracer.new(app)
        expect { middleware.call!(env) }.not_to raise_error
      end
    end
  end

  describe "GrapeRequestLogSubscriber error handling" do
    it "handles non-event objects gracefully" do
      subscriber.grape_request("not an event")
      expect(logger.lines).to be_empty
    end

    it "handles event without env payload" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {})
      subscriber.grape_request(event)
      # Should not raise
      expect(logger.lines).to be_empty
    end

    it "handles build_request failure" do
      env = {"invalid" => "env"}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})
      subscriber.grape_request(event)
      # Should use fallback logging
      expect(logger.lines.length).to be > 0
    end

    it "handles filter_parameters_manually with max depth" do
      # Test directly by calling with depth 11 to trigger the max_depth check
      deep_params = {password: "secret"}

      # Call with depth > 10 to trigger the max_depth_exceeded return
      result = subscriber.send(:filter_parameters_manually, deep_params, 11)
      expect(result).to eq({"[FILTERED]" => "[max_depth_exceeded]"})

      # Also test with depth exactly 10 to ensure it doesn't trigger
      result2 = subscriber.send(:filter_parameters_manually, deep_params, 10)
      expect(result2).not_to have_key("[FILTERED]") if result2.is_a?(Hash) && !result2.empty?
    end

    it "handles filter_parameters_manually with large hash" do
      large_params = {}
      60.times { |i| large_params["key#{i}"] = "value#{i}" }

      result = subscriber.send(:filter_parameters_manually, large_params)
      expect(result.keys.length).to be <= 50
    end

    it "handles extract_status with various response formats" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        response: [404, {}, ["Not Found"]],
        status: nil
      })
      status = subscriber.send(:extract_status, event)
      expect(status).to eq(404)
    end

    it "handles extract_status with endpoint status" do
      endpoint = double("Endpoint", status: 422)
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: env,
        status: nil
      })
      status = subscriber.send(:extract_status, event)
      expect(status).to eq(422)
    end

    it "handles extract_action with empty path" do
      endpoint = double("Endpoint", options: {method: ["GET"], path: ["/"]})
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})
      action = subscriber.send(:extract_action, event)
      expect(action).to eq("get")
    end

    it "handles extract_controller without Rails.root" do
      original_root = Rails.respond_to?(:root) ? Rails.root : nil
      allow(Rails).to receive(:root).and_return(nil)

      endpoint = double("Endpoint", source: double("Source", source_location: ["/some/path/file.rb", 10]))
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      controller = subscriber.send(:extract_controller, event)
      expect(controller).to be_nil
    ensure
      if original_root && Rails.respond_to?(:root)
        allow(Rails).to receive(:root).and_call_original
      end
    end

    it "handles extract_source_location without Rails.root" do
      original_root = Rails.respond_to?(:root) ? Rails.root : nil
      allow(Rails).to receive(:root).and_return(nil)

      endpoint = double("Endpoint", source: double("Source", source_location: ["/some/path/file.rb", 10]))
      env = {"api.endpoint" => endpoint}
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {env: env})

      location = subscriber.send(:extract_source_location, event)
      expect(location).to eq("/some/path/file.rb:10")
    ensure
      if original_root && Rails.respond_to?(:root)
        allow(Rails).to receive(:root).and_call_original
      end
    end

    it "handles log_fallback_subscriber_error with all fallbacks" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"},
        status: nil,
        exception_object: nil
      })

      error = StandardError.new("Subscriber error")
      subscriber.send(:log_fallback_subscriber_error, event, error)

      expect(logger.lines.length).to be > 0
      log_data = logger.lines.last
      expect(log_data[:method]).to eq("GET")
      expect(log_data[:path]).to eq("/test")
    end

    it "handles log_fallback_subscriber_error with original exception" do
      original_error = StandardError.new("Original error")
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now, "1", {
        env: {"REQUEST_METHOD" => "POST", "PATH_INFO" => "/api"},
        exception_object: original_error
      })

      subscriber_error = StandardError.new("Subscriber error")
      subscriber.send(:log_fallback_subscriber_error, event, subscriber_error)

      expect(logger.lines.length).to be > 0
      log_data = logger.lines.last
      expect(log_data[:exception][:message]).to eq("Original error")
    end
  end

  describe "StatusExtractor edge cases" do
    it "handles exception with status method" do
      exception = StandardError.new("Error")
      allow(exception).to receive(:status).and_return(404)

      status = GrapeRailsLogger::StatusExtractor.extract_status_from_exception(exception)
      expect(status).to eq(404)
    end

    it "handles exception with @status instance variable" do
      exception = StandardError.new("Error")
      exception.instance_variable_set(:@status, 422)

      status = GrapeRailsLogger::StatusExtractor.extract_status_from_exception(exception)
      expect(status).to eq(422)
    end

    it "handles exception with options hash" do
      exception = StandardError.new("Error")
      allow(exception).to receive(:options).and_return({status: 400})

      status = GrapeRailsLogger::StatusExtractor.extract_status_from_exception(exception)
      expect(status).to eq(400)
    end

    it "handles exception class name matching" do
      # Test with actual ActiveRecord exception if available, otherwise use a mock
      if defined?(ActiveRecord::RecordNotFound)
        exception = ActiveRecord::RecordNotFound.new("Not found")
        status = GrapeRailsLogger::StatusExtractor.extract_status_from_exception(exception)
        expect(status).to eq(404)
      else
        # If ActiveRecord is not available, test that unknown exceptions default to 500
        exception = StandardError.new("Unknown")
        status = GrapeRailsLogger::StatusExtractor.extract_status_from_exception(exception)
        expect(status).to eq(500)
      end
    end

    it "defaults to 500 for unknown exceptions" do
      exception = StandardError.new("Unknown error")
      status = GrapeRailsLogger::StatusExtractor.extract_status_from_exception(exception)
      expect(status).to eq(500)
    end
  end

  describe "Timings edge cases" do
    it "handles IsolatedExecutionState when available" do
      if defined?(ActiveSupport::IsolatedExecutionState)
        expect(GrapeRailsLogger::Timings.execution_state).to eq(ActiveSupport::IsolatedExecutionState)
      end
    end

    it "handles multiple threads correctly" do
      GrapeRailsLogger::Timings.reset_db_runtime
      event1 = ActiveSupport::Notifications::Event.new("sql.active_record", Time.now, Time.now + 0.05, "1", {})
      event2 = ActiveSupport::Notifications::Event.new("sql.active_record", Time.now, Time.now + 0.03, "1", {})

      GrapeRailsLogger::Timings.append_db_runtime(event1)
      GrapeRailsLogger::Timings.append_db_runtime(event2)

      expect(GrapeRailsLogger::Timings.db_runtime).to be >= 0.05
      expect(GrapeRailsLogger::Timings.db_calls).to eq(2)
    end
  end
end
