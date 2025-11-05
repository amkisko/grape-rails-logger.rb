require "spec_helper"
require "rack/mock"
require "logger"
require_relative "support/logger_stub"

RSpec.describe GrapeRailsLogger::EndpointWrapper do
  let(:logger) { TestLogger.new }
  let(:app) { ->(env) { [200, {}, ["OK"]] } }

  before do
    Rails._logger = logger
  end

  describe "#initialize" do
    it "stores app and endpoint" do
      endpoint = double("Endpoint")
      wrapper = described_class.new(app, endpoint)

      expect(wrapper.instance_variable_get(:@app)).to be(app)
      expect(wrapper.instance_variable_get(:@endpoint)).to be(endpoint)
    end
  end

  describe "#call" do
    context "when enabled is false" do
      it "calls app directly without instrumentation" do
        allow(GrapeRailsLogger).to receive(:effective_config).and_return(
          double(enabled: false, logger: nil)
        )

        wrapper = described_class.new(app, nil)
        env = Rack::MockRequest.env_for("/test")

        expect(ActiveSupport::Notifications).not_to receive(:instrument)
        response = wrapper.call(env)
        expect(response[0]).to eq(200)
      end
    end

    context "when enabled is true" do
      before do
        allow(GrapeRailsLogger).to receive(:effective_config).and_return(
          double(enabled: true, logger: nil)
        )
      end

      it "instruments the request" do
        wrapper = described_class.new(app, nil)
        env = Rack::MockRequest.env_for("/test")

        received_payload = nil
        ActiveSupport::Notifications.subscribe("grape.request") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          received_payload = event.payload
        end

        wrapper.call(env)

        expect(received_payload).to be_a(Hash)
        expect(received_payload[:env]).to be_a(Hash)
      end

      it "resets DB runtime before request" do
        wrapper = described_class.new(app, nil)
        env = Rack::MockRequest.env_for("/test")

        expect(GrapeRailsLogger::Timings).to receive(:reset_db_runtime)
        wrapper.call(env)
      end

      it "collects response metadata" do
        wrapper = described_class.new(app, nil)
        env = Rack::MockRequest.env_for("/test")

        received_payload = nil
        ActiveSupport::Notifications.subscribe("grape.request") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          received_payload = event.payload
        end

        wrapper.call(env)

        expect(received_payload[:status]).to eq(200)
        expect(received_payload[:response]).to be_an(Array)
        expect(received_payload[:db_runtime]).to be_a(Numeric)
        expect(received_payload[:db_calls]).to be_a(Integer)
      end

      it "handles instrumentation errors gracefully" do
        allow(ActiveSupport::Notifications).to receive(:instrument).and_raise(StandardError, "Instrumentation failed")

        wrapper = described_class.new(app, nil)
        env = Rack::MockRequest.env_for("/test")

        response = wrapper.call(env)
        expect(response[0]).to eq(200)
      end

      it "calls app even when instrumentation fails" do
        allow(ActiveSupport::Notifications).to receive(:instrument).and_raise(StandardError, "Failed")

        wrapper = described_class.new(app, nil)
        env = Rack::MockRequest.env_for("/test")

        response = wrapper.call(env)
        expect(response[0]).to eq(200)
      end
    end
  end

  describe "#resolve_logger" do
    context "when config has a logger" do
      it "uses config logger" do
        custom_logger = TestLogger.new
        allow(GrapeRailsLogger).to receive(:effective_config).and_return(
          double(enabled: true, logger: custom_logger)
        )

        wrapper = described_class.new(app, nil)
        logger = wrapper.send(:resolve_logger)

        expect(logger).to be(custom_logger)
      end
    end

    context "when config logger is nil and Rails is available" do
      it "uses Rails.logger" do
        rails_logger = TestLogger.new
        allow(GrapeRailsLogger).to receive(:effective_config).and_return(
          double(enabled: true, logger: nil)
        )
        # Rails is already defined in the test environment
        allow(Rails).to receive(:logger).and_return(rails_logger)

        wrapper = described_class.new(app, nil)
        logger = wrapper.send(:resolve_logger)

        expect(logger).to be(rails_logger)
      end
    end

    context "when config logger is nil and Rails.logger is nil" do
      it "creates a new Logger to stdout" do
        allow(GrapeRailsLogger).to receive(:effective_config).and_return(
          double(enabled: true, logger: nil)
        )
        allow(Rails).to receive(:logger).and_return(nil)

        wrapper = described_class.new(app, nil)
        logger = wrapper.send(:resolve_logger)

        expect(logger).to be_a(Logger)
        expect(logger.instance_variable_get(:@logdev).dev).to eq($stdout)
      end
    end
  end

  describe "#collect_response_metadata" do
    let(:wrapper) { described_class.new(app, nil) }
    let(:response) { [201, {"Content-Type" => "application/json"}, ["Created"]] }
    let(:env) { Rack::MockRequest.env_for("/test") }
    let(:payload) { {} }

    before do
      allow(GrapeRailsLogger::Timings).to receive(:db_runtime).and_return(0)
      allow(GrapeRailsLogger::Timings).to receive(:db_calls).and_return(0)
    end

    it "extracts status from response" do
      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:status]).to eq(201)
      expect(payload[:response]).to be(response)
    end

    it "handles nil status gracefully" do
      response_obj = Object.new

      wrapper.send(:collect_response_metadata, response_obj, env, payload, Time.now)

      expect(payload[:status]).to be_nil
      expect(payload[:response]).to be(response_obj)
    end

    it "extracts exception from endpoint.options[:exception]" do
      exception = StandardError.new("Test error")
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(true)
      allow(endpoint).to receive(:options).and_return(exception: exception)
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(false)

      env[Grape::Env::API_ENDPOINT] = endpoint

      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:exception_object]).to be(exception)
    end

    it "extracts exception from endpoint.options['exception']" do
      exception = StandardError.new("Test error")
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(true)
      allow(endpoint).to receive(:options).and_return("exception" => exception)
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(false)

      env[Grape::Env::API_ENDPOINT] = endpoint

      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:exception_object]).to be(exception)
    end

    it "extracts exception from endpoint.options[:error]" do
      exception = StandardError.new("Test error")
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(true)
      allow(endpoint).to receive(:options).and_return(error: exception)
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(false)

      env[Grape::Env::API_ENDPOINT] = endpoint

      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:exception_object]).to be(exception)
    end

    it "extracts exception from endpoint.options['error']" do
      exception = StandardError.new("Test error")
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(true)
      allow(endpoint).to receive(:options).and_return("error" => exception)
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(false)

      env[Grape::Env::API_ENDPOINT] = endpoint

      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:exception_object]).to be(exception)
    end

    it "extracts exception from endpoint.exception when options don't have it" do
      exception = StandardError.new("Test error")
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(true)
      allow(endpoint).to receive(:options).and_return({})
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(true)
      allow(endpoint).to receive(:exception).and_return(exception)

      env[Grape::Env::API_ENDPOINT] = endpoint

      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:exception_object]).to be(exception)
    end

    it "prefers options exception over endpoint.exception" do
      options_exception = StandardError.new("Options error")
      endpoint_exception = StandardError.new("Endpoint error")
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(true)
      allow(endpoint).to receive(:options).and_return(exception: options_exception)
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(true)
      allow(endpoint).to receive(:exception).and_return(endpoint_exception)

      env[Grape::Env::API_ENDPOINT] = endpoint

      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:exception_object]).to be(options_exception)
    end

    it "ignores non-Exception objects in options" do
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(true)
      allow(endpoint).to receive(:options).and_return(exception: "not an exception")
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(false)

      env[Grape::Env::API_ENDPOINT] = endpoint

      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:exception_object]).to be_nil
    end

    it "handles endpoint without respond_to?(:options)" do
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(false)
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(false)

      env[Grape::Env::API_ENDPOINT] = endpoint

      expect { wrapper.send(:collect_response_metadata, response, env, payload, Time.now) }.not_to raise_error
    end

    it "handles endpoint.options that is not a Hash" do
      endpoint = double("Endpoint")
      allow(endpoint).to receive(:respond_to?).with(:options).and_return(true)
      allow(endpoint).to receive(:options).and_return("not a hash")
      allow(endpoint).to receive(:respond_to?).with(:exception).and_return(false)

      env[Grape::Env::API_ENDPOINT] = endpoint

      expect { wrapper.send(:collect_response_metadata, response, env, payload, Time.now) }.not_to raise_error
    end

    it "handles env that is not a Hash" do
      non_hash_env = "not a hash"

      expect { wrapper.send(:collect_response_metadata, response, non_hash_env, payload, Time.now) }.not_to raise_error
    end

    it "handles missing API_ENDPOINT in env" do
      env_without_endpoint = {"REQUEST_METHOD" => "GET"}

      expect { wrapper.send(:collect_response_metadata, response, env_without_endpoint, payload, Time.now) }.not_to raise_error
    end

    it "captures DB metrics from Timings" do
      allow(GrapeRailsLogger::Timings).to receive(:db_runtime).and_return(12.34)
      allow(GrapeRailsLogger::Timings).to receive(:db_calls).and_return(5)

      wrapper.send(:collect_response_metadata, response, env, payload, Time.now)

      expect(payload[:db_runtime]).to eq(12.34)
      expect(payload[:db_calls]).to eq(5)
    end
  end

  describe "#extract_status_from_response" do
    let(:wrapper) { described_class.new(app, nil) }

    it "extracts status from array response" do
      response = [404, {}, ["Not Found"]]
      status = wrapper.send(:extract_status_from_response, response)
      expect(status).to eq(404)
    end

    it "extracts status from response with to_a method" do
      response_obj = Class.new do
        def to_a
          [418, {}, ["I'm a teapot"]]
        end
      end.new

      status = wrapper.send(:extract_status_from_response, response_obj)
      expect(status).to eq(418)
    end

    it "handles to_a returning non-array" do
      response_obj = Class.new do
        def to_a
          "not an array"
        end
      end.new

      status = wrapper.send(:extract_status_from_response, response_obj)
      expect(status).to be_nil
    end

    it "handles to_a returning array with non-integer first element" do
      response_obj = Class.new do
        def to_a
          ["not an integer", {}, []]
        end
      end.new

      status = wrapper.send(:extract_status_from_response, response_obj)
      expect(status).to be_nil
    end

    it "extracts status from response with status method" do
      response_obj = double("Response", status: 422)
      status = wrapper.send(:extract_status_from_response, response_obj)
      expect(status).to eq(422)
    end

    it "handles status method returning non-integer" do
      response_obj = double("Response", status: "422")
      status = wrapper.send(:extract_status_from_response, response_obj)
      expect(status).to be_nil
    end

    it "returns nil for nil response" do
      status = wrapper.send(:extract_status_from_response, nil)
      expect(status).to be_nil
    end

    it "returns nil for unknown response types" do
      status = wrapper.send(:extract_status_from_response, "string response")
      expect(status).to be_nil

      status = wrapper.send(:extract_status_from_response, Object.new)
      expect(status).to be_nil
    end

    it "handles response with both to_a and status method (prefers to_a)" do
      response_obj = Class.new do
        def to_a
          [499, {}, []]
        end

        def status
          422
        end
      end.new

      status = wrapper.send(:extract_status_from_response, response_obj)
      expect(status).to eq(499)
    end
  end

  describe "#handle_instrumentation_error" do
    it "does not raise errors" do
      wrapper = described_class.new(app, nil)
      error = StandardError.new("Test error")

      expect { wrapper.send(:handle_instrumentation_error, error) }.not_to raise_error
    end
  end
end
