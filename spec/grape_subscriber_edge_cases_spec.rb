require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "GrapeRequestLogSubscriber edge cases" do
  let(:logger) { TestLogger.new }
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }

  before do
    Rails._logger = logger
  end

  describe "error handling" do
    it "handles nil env gracefully" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {env: nil})
      expect { subscriber.grape_request(event) }.not_to raise_error
      expect(logger.lines).to be_empty
    end

    it "handles non-hash env gracefully" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {env: "not a hash"})
      expect { subscriber.grape_request(event) }.not_to raise_error
      expect(logger.lines).to be_empty
    end

    it "handles Grape::Request build failure" do
      env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      allow(::Grape::Request).to receive(:new).and_raise(StandardError.new("Request build failed"))
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {env: env})

      # Should not raise error
      expect { subscriber.grape_request(event) }.not_to raise_error
    end

    it "handles logger failure with stderr fallback" do
      error_logger = Class.new do
        def info(*)
          raise StandardError, "Logger broken"
        end

        def error(*)
          raise StandardError, "Logger broken"
        end
      end.new

      allow(Rails).to receive(:logger).and_return(error_logger)
      env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      request = double("Request", request_method: "GET", path: "/test", host: "example.com", ip: "127.0.0.1", params: {}, env: env)
      allow(::Grape::Request).to receive(:new).and_return(request)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {env: env})

      expect { subscriber.grape_request(event) }.not_to raise_error
    end
  end

  describe "extract_status edge cases" do
    it "handles missing status and exception" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"}
      })
      status = subscriber.send(:extract_status, event)
      expect(status).to eq(200) # Default fallback
    end

    it "handles non-integer status values" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"},
        status: "not an integer"
      })
      status = subscriber.send(:extract_status, event)
      expect(status).to eq(200) # Default fallback
    end

    it "extracts status from response array" do
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"},
        response: [404, {}, []]
      })
      status = subscriber.send(:extract_status, event)
      expect(status).to eq(404)
    end

    it "extracts status from endpoint when available" do
      endpoint = double("Endpoint", status: 503)
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test", "api.endpoint" => endpoint}
      })
      status = subscriber.send(:extract_status, event)
      expect(status).to eq(503)
    end

    it "handles endpoint without status method" do
      endpoint = double("Endpoint")
      event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
        env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test", "api.endpoint" => endpoint}
      })
      status = subscriber.send(:extract_status, event)
      expect(status).to eq(200) # Default fallback
    end
  end

  describe "safe_string edge cases" do
    it "handles nil values" do
      expect(subscriber.send(:safe_string, nil)).to be_nil
    end

    it "handles objects that raise on to_s" do
      obj = Object.new
      def obj.to_s
        raise StandardError, "to_s failed"
      end
      expect(subscriber.send(:safe_string, obj)).to be_nil
    end

    it "converts non-nil values to string" do
      expect(subscriber.send(:safe_string, 123)).to eq("123")
      expect(subscriber.send(:safe_string, :symbol)).to eq("symbol")
    end
  end

  describe "extract_params edge cases" do
    it "handles request without params" do
      request = double("Request", params: nil, env: {})
      params = subscriber.send(:extract_params, request)
      expect(params).to eq({})
    end

    it "handles params extraction failure" do
      params_obj = double("Params")
      allow(params_obj).to receive(:respond_to?).and_return(false)
      allow(params_obj).to receive(:empty?).and_raise(StandardError)
      request = double("Request", params: params_obj, env: {})
      params = subscriber.send(:extract_params, request)
      expect(params).to eq({})
    end
  end

  describe "extract_format edge cases" do
    it "defaults to json when format unavailable" do
      request = double("Request", try: nil, env: {})
      format = subscriber.send(:extract_format, request)
      expect(format).to eq("json")
    end

    it "handles request without try method" do
      request = Object.new
      allow(request).to receive(:env).and_return({"api.format" => ".xml"})
      format = subscriber.send(:extract_format, request)
      expect(format).to eq("xml")
    end
  end

  describe "build_exception_data edge cases" do
    it "handles exception without backtrace" do
      ex = StandardError.new("test")
      allow(ex).to receive(:backtrace).and_return(nil)
      data = subscriber.send(:build_exception_data, ex)
      expect(data[:class]).to eq("StandardError")
      expect(data[:message]).to eq("test")
      expect(data[:backtrace]).to be_nil
    end

    it "handles exception data extraction failure" do
      ex = StandardError.new("test")
      allow(ex).to receive(:class).and_raise(StandardError, "class failed")
      data = subscriber.send(:build_exception_data, ex)
      expect(data[:class]).to eq("Unknown")
      expect(data[:message]).to include("Failed to extract")
    end
  end
end
