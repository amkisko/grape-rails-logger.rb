require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe "build_log_data edge cases" do
  let(:subscriber) { GrapeRailsLogger::GrapeRequestLogSubscriber.new }

  it "handles nil duration gracefully" do
    # Create event with nil end time to cause duration calculation to fail
    start_time = Time.now
    event = ActiveSupport::Notifications::Event.new("grape.request", start_time, nil, "1", {})
    request = double("Request", request_method: "GET", path: "/test", host: "example.com", ip: "127.0.0.1", params: {}, env: {})
    env = {}

    data = subscriber.send(:build_log_data, event, request, env)
    expect(data[:duration]).to eq(0)
  end

  it "handles missing db_runtime and db_calls" do
    event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {})
    request = double("Request", request_method: "GET", path: "/test", host: "example.com", ip: "127.0.0.1", params: {}, env: {})
    env = {}

    data = subscriber.send(:build_log_data, event, request, env)
    expect(data[:db]).to eq(0)
    expect(data[:db_calls]).to eq(0)
  end

  it "rounds duration and db_runtime" do
    start_time = Time.now
    end_time = start_time + 0.012345
    event = ActiveSupport::Notifications::Event.new("grape.request", start_time, end_time, "1", {
      db_runtime: 0.056789,
      db_calls: 2
    })
    # Mock duration to return the expected value
    allow(event).to receive(:duration).and_return(0.012345)
    request = double("Request", request_method: "GET", path: "/test", host: "example.com", ip: "127.0.0.1", params: {}, env: {})
    env = {}

    data = subscriber.send(:build_log_data, event, request, env)
    expect(data[:duration]).to eq(0.01) # Rounded to 2 decimals
    expect(data[:db]).to eq(0.06) # Rounded to 2 decimals
  end

  it "extracts request_id from env" do
    event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {})
    request = double("Request", request_method: "GET", path: "/test", host: "example.com", ip: "127.0.0.1", params: {}, env: {})
    env = {"action_dispatch.request_id" => "req-abc-123"}

    data = subscriber.send(:build_log_data, event, request, env)
    expect(data[:request_id]).to eq("req-abc-123")
  end

  it "handles nil request_id" do
    event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {})
    request = double("Request", request_method: "GET", path: "/test", host: "example.com", ip: "127.0.0.1", params: {}, env: {})
    env = {}

    data = subscriber.send(:build_log_data, event, request, env)
    expect(data[:request_id]).to be_nil
  end
end
