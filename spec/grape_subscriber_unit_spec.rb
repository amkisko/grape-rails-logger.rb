require "spec_helper"

RSpec.describe GrapeRailsLogger::GrapeRequestLogSubscriber do
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
    # Also ensure Rails.logger returns the test logger
    allow(Rails).to receive(:logger).and_return(logger) if defined?(Rails)
  end

  def build_event(payload_overrides = {})
    endpoint_options = {method: [:GET], path: ["/users/:id"]}
    source_location = [File.join(Rails.root.to_s, "app/api/users.rb"), 123]

    endpoint = Object.new
    endpoint.define_singleton_method(:options) { endpoint_options }
    endpoint.define_singleton_method(:source) do
      src = Object.new
      src.define_singleton_method(:source_location) { source_location }
      src
    end
    endpoint.define_singleton_method(:status) { 202 }
    endpoint.define_singleton_method(:respond_to?) { |method| [:options, :source, :status].include?(method) }

    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/users/1",
      "api.endpoint" => endpoint,
      Grape::Env::API_ENDPOINT => endpoint,
      "api.format" => ".json",
      "action_dispatch.request_id" => "req-123"
    }

    payload = {
      env: env,
      db_runtime: 12.34,
      db_calls: 2,
      response: [201, {"Content-Type" => "application/json"}, []]
    }.merge(payload_overrides)

    ActiveSupport::Notifications::Event.new(
      "grape.request", Time.now, Time.now + 0.01, SecureRandom.hex(4), payload
    )
  end

  it "builds structured data with controller, action, source and status" do
    # build_event already includes db_runtime: 12.34, db_calls: 2 in payload
    # Don't override status - use the default response status
    # Need to pass logger in payload
    event = build_event(logger: logger)
    described_class.new.grape_request(event)

    entry = logger.lines.find { |l| l.is_a?(Hash) }
    expect(entry).to be_a(Hash)
    # Status comes from response array [201, ...]
    expect(entry[:status]).to eq(201)
    expect(entry[:format]).to eq("json")
    # db_runtime should be logged as :db
    expect(entry[:db]).to eq(12.34)
    expect(entry[:db_calls]).to eq(2)
    expect(entry[:method]).to eq("GET")
    expect(entry[:path]).to eq("/users/1")
    # Controller and action require endpoint with proper source location
    expect(entry[:controller]).to eq("Users")
    expect(entry[:action]).to eq("get_users_id")
  end

  it "derives status from api.endpoint when not present in payload" do
    endpoint_options = {method: [:POST], path: ["/items"]}
    source_location = [File.join(Rails.root.to_s, "app/api/items.rb"), 5]

    endpoint = Object.new
    endpoint.define_singleton_method(:options) { endpoint_options }
    endpoint.define_singleton_method(:source) do
      src = Object.new
      src.define_singleton_method(:source_location) { source_location }
      src
    end
    endpoint.define_singleton_method(:status) { 422 }
    endpoint.define_singleton_method(:respond_to?) { |method| [:options, :source, :status].include?(method) }

    env = build_event.payload[:env].merge("api.endpoint" => endpoint, Grape::Env::API_ENDPOINT => endpoint)
    event = build_event(response: nil, env: env, status: nil)
    described_class.new.grape_request(event)

    entry = logger.lines.find { |l| l.is_a?(Hash) }
    expect(entry).to be_a(Hash)
    # Status extraction from endpoint requires error status (>= 400)
    expect(entry[:status]).to eq(422)
  end

  it "computes action for root path" do
    endpoint_options = {method: [:GET], path: ["/"]}
    source_location = [File.join(Rails.root.to_s, "app/api/root.rb"), 1]

    endpoint = Object.new
    endpoint.define_singleton_method(:options) { endpoint_options }
    endpoint.define_singleton_method(:source) do
      src = Object.new
      src.define_singleton_method(:source_location) { source_location }
      src
    end
    endpoint.define_singleton_method(:status) { 200 }
    endpoint.define_singleton_method(:respond_to?) { |method| [:options, :source, :status].include?(method) }

    # Replace the endpoint in env - extract_action uses "api.endpoint" string key
    env = build_event.payload[:env].dup
    env["api.endpoint"] = endpoint
    # Also set the constant key for completeness
    env[Grape::Env::API_ENDPOINT] = endpoint
    event = build_event(env: env, logger: logger)
    described_class.new.grape_request(event)

    entry = logger.lines.find { |l| l.is_a?(Hash) }
    expect(entry).to be_a(Hash)
    expect(entry[:action]).to eq("get")
  end

  it "defaults format to json when none provided" do
    env = build_event.payload[:env].dup
    env.delete("api.format")
    env.delete("rack.request.formats")
    event = build_event(env: env)
    described_class.new.grape_request(event)

    entry = logger.lines.find { |l| l.is_a?(Hash) }
    expect(entry).to be_a(Hash)
    expect(entry[:format]).to eq("json")
  end

  it "handles missing endpoint gracefully" do
    # Create a new event with env that has no endpoint
    # extract_params requires endpoint, so we need to handle that
    env = {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/test",
      "api.format" => ".json"
    }

    payload = {
      env: env,
      db_runtime: 0,
      db_calls: 0,
      response: [200, {"Content-Type" => "application/json"}, []],
      logger: logger
    }

    event = ActiveSupport::Notifications::Event.new(
      "grape.request", Time.now, Time.now + 0.01, SecureRandom.hex(4), payload
    )

    # Mock build_request to return nil when there's no endpoint
    allow_any_instance_of(described_class).to receive(:build_request).and_return(nil)

    described_class.new.grape_request(event)

    entry = logger.lines.find { |l| l.is_a?(Hash) }
    expect(entry).to be_a(Hash)
    # Without endpoint, extract_action should return "unknown"
    # extract_params will return {} when no endpoint, which is fine
    expect(entry[:action]).to eq("unknown")
    expect(entry[:controller]).to be_nil
  end

  it "logs error with exception details and backtrace in non-production" do
    ex = StandardError.new("conflict")
    event = build_event(exception_object: ex)
    described_class.new.grape_request(event)

    entry = logger.lines.find { |o| o.is_a?(Hash) && o[:exception] }
    expect(entry[:exception][:class]).to match(/StandardError/)
    expect(entry[:exception][:message]).to eq("conflict")
  end

  it "extracts format from rack.request.formats when api.format missing" do
    env = build_event.payload[:env].dup
    env.delete("api.format")
    env["rack.request.formats"] = [".json"]
    event = build_event(env: env)
    described_class.new.grape_request(event)

    entry = logger.lines.find { |l| l.is_a?(Hash) }
    expect(entry).to be_a(Hash)
    expect(entry[:format]).to eq("json")
  end
end
