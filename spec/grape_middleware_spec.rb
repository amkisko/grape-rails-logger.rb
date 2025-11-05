require "spec_helper"
require "rack/mock"

RSpec.describe GrapeRailsLogger::GrapeInstrumentation do
  let(:api_class) do
    Class.new(Grape::API) do
      format :json
      use GrapeRailsLogger::GrapeInstrumentation

      get "/ok" do
        {status: "ok"}
      end

      get "/error" do
        error!("nope", 418)
      end

      get "/boom" do
        raise StandardError, "boom"
      end
    end
  end

  let(:app) { api_class }

  it "emits notification and sets status for success" do
    received = nil
    sub = ActiveSupport::Notifications.subscribe("grape.request") { |*args| received = ActiveSupport::Notifications::Event.new(*args) }

    response = Rack::MockRequest.new(app).get("/ok")
    expect(response.status).to eq(200)

    expect(received).to be
    expect(received.payload[:status]).to eq(200)
    expect(received.payload[:db_runtime]).to be_a(Numeric)
    expect(received.payload[:db_calls]).to be_a(Numeric)
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "emits notification and sets status for error!" do
    received = nil
    sub = ActiveSupport::Notifications.subscribe("grape.request") { |*args| received = ActiveSupport::Notifications::Event.new(*args) }

    response = Rack::MockRequest.new(app).get("/error")
    expect(response.status).to eq(418)
    expect(received).to be
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "captures exception object for unhandled exceptions" do
    received = nil
    sub = ActiveSupport::Notifications.subscribe("grape.request") { |*args| received = ActiveSupport::Notifications::Event.new(*args) }

    expect { Rack::MockRequest.new(app).get("/boom") }.to raise_error(StandardError, /boom/)
    expect(received.payload[:exception_object]).to be_a(StandardError)
    expect(received.payload[:status]).to eq(500)
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "sets status from exception.status when raised" do
    custom_error = Class.new(StandardError) do
      def status = 499
    end

    received = nil
    sub = ActiveSupport::Notifications.subscribe("grape.request") { |*args| received = ActiveSupport::Notifications::Event.new(*args) }

    app2 = Class.new(Grape::API) do
      format :json
      use GrapeRailsLogger::GrapeInstrumentation
      get "/boom_status" do
        raise custom_error, "x"
      end
    end

    expect { Rack::MockRequest.new(app2).get("/boom_status") }.to raise_error(custom_error)
    expect(received.payload[:status]).to eq(499)
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  it "sets status from exception.options[:status] when raised" do
    custom_error = Class.new(StandardError) do
      attr_reader :options
      def initialize
        @options = {status: 422}
        super
      end
    end

    received = nil
    sub = ActiveSupport::Notifications.subscribe("grape.request") { |*args| received = ActiveSupport::Notifications::Event.new(*args) }

    app2 = Class.new(Grape::API) do
      format :json
      use GrapeRailsLogger::GrapeInstrumentation
      get "/boom_opts" do
        raise custom_error
      end
    end

    expect { Rack::MockRequest.new(app2).get("/boom_opts") }.to raise_error(custom_error)
    expect(received.payload[:status]).to eq(422)
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  describe "response handling" do
    it "handles response object without status attribute" do
      response_obj = Object.new
      app = Class.new(Grape::API) do
        format :json
        use GrapeRailsLogger::GrapeInstrumentation
        get("/unknown") { response_obj }
      end

      received = nil
      sub = ActiveSupport::Notifications.subscribe("grape.request") { |*args| received = ActiveSupport::Notifications::Event.new(*args) }

      Rack::MockRequest.new(app).get("/unknown")
      expect(received.payload[:status]).to eq(200)
    ensure
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end

    it "handles exception without response" do
      custom_error = Class.new(StandardError) { def status = 404 }.new
      app = Class.new(Grape::API) do
        format :json
        use GrapeRailsLogger::GrapeInstrumentation
        get("/error") { raise custom_error, "Not found" }
      end

      received = nil
      sub = ActiveSupport::Notifications.subscribe("grape.request") { |*args| received = ActiveSupport::Notifications::Event.new(*args) }

      begin
        Rack::MockRequest.new(app).get("/error")
      rescue
        # Exception is raised and caught by middleware
      end

      expect(received).to be
      expect(received.payload[:exception_object]).to be
      expect(received.payload[:status]).to eq(404)
    ensure
      ActiveSupport::Notifications.unsubscribe(sub) if sub
    end
  end
end
