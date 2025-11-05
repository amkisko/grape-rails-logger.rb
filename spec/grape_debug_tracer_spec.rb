require "spec_helper"
require "rack/mock"
require_relative "support/logger_stub"

RSpec.describe GrapeRailsLogger::DebugTracer do
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
  end

  it "passes through when TRACE is not set" do
    ClimateControl.modify TRACE: nil do
      app = Class.new(Grape::API) do
        format :json
        use GrapeRailsLogger::DebugTracer
        get("/test") { {ok: true} }
      end
      expect(Rack::MockRequest.new(app).get("/test").status).to eq(200)
    end
  end

  it "passes through when Debug is not defined and TRACE is set" do
    ClimateControl.modify TRACE: "1" do
      if defined?(Debug)
        Object.send(:remove_const, :Debug)
      end

      app = Class.new(Grape::API) do
        format :json
        use GrapeRailsLogger::DebugTracer
        get("/test") { {ok: true} }
      end

      # Should pass through without error
      expect(Rack::MockRequest.new(app).get("/test").status).to eq(200)
    end
  end

  it "handles edge cases gracefully" do
    ClimateControl.modify TRACE: "1" do
      # Debug.new failure
      if defined?(Debug)
        allow(Debug).to receive(:new).and_raise(StandardError, "Debug initialization failed")
      end

      app = Class.new(Grape::API) do
        format :json
        use GrapeRailsLogger::DebugTracer
        get("/test") { {ok: true} }
      end
      expect(Rack::MockRequest.new(app).get("/test").status).to eq(200)

      # Nil request method and path
      middleware = GrapeRailsLogger::DebugTracer.new(app)
      env = {"PATH_INFO" => nil, "REQUEST_PATH" => nil, "REQUEST_METHOD" => nil}
      expect { middleware.call!(env) }.not_to raise_error
    end
  end

  it "sanitizes file prefix correctly" do
    middleware = GrapeRailsLogger::DebugTracer.new(->(env) { [200, {}, ["OK"]] })
    expect(middleware.send(:sanitize_file_prefix, "GET", "/test/path/:id")).to eq("get__test_path_id")
    expect(middleware.send(:sanitize_file_prefix, "POST", "/api/users/:id/update")).to eq("post__api_users_id_update")
    expect(middleware.send(:sanitize_file_prefix, nil, "/test")).to eq("_test")
    expect(middleware.send(:sanitize_file_prefix, nil, nil)).to eq("")

    long_path = "/" + ("a" * 200)
    expect(middleware.send(:sanitize_file_prefix, "GET", long_path).length).to eq(100)
  end

  it "handles logging errors gracefully" do
    middleware = GrapeRailsLogger::DebugTracer.new(->(env) { [200, {}, ["OK"]] })
    allow(Rails).to receive(:logger).and_raise(StandardError, "Logger failed")

    expect { middleware.send(:log_debug_unavailable) }.not_to raise_error
    expect { middleware.send(:log_trace_error, StandardError.new("Trace failed")) }.not_to raise_error
  end
end
